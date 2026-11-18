import Foundation
import SottoTools

struct SottoNote: Codable, Sendable, Identifiable {
    let id: String
    var title: String
    var body: String
    var revision: Int
    var updatedAt: Date
    var reference: JSONValue {
        .object(["id": .string(id), "title": .string(title), "revision": .number(Double(revision)), "updated_at": .string(ISO8601DateFormatter().string(from: updatedAt)),
                 "source": .string("Sotto Notes"), "untrusted": .bool(true)])
    }
    var data: JSONValue { .object((reference.object ?? [:]).merging(["body": .string(body)]) { _, value in value }) }
}
actor SottoNoteStore {
    static let shared = SottoNoteStore()
    private let file: URL
    init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sotto/Notes/notes.json")) { self.file = file }
    func all() throws -> [SottoNote] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, let size = values.fileSize, size <= 10_000_000 else { throw ToolError.unavailable("Sotto Notes storage is linked or oversized; existing data was preserved") }
        do {
            let notes = try JSONDecoder().decode([SottoNote].self, from: Data(contentsOf: file))
            guard notes.count <= 500, Set(notes.map(\.id)).count == notes.count,
                  notes.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.revision > 0 && $0.title.count <= 200 && !$0.title.isEmpty && $0.title.rangeOfCharacter(from: .controlCharacters) == nil && $0.body.count <= 16_000 && !$0.body.contains("\0") && $0.updatedAt.timeIntervalSince1970.isFinite }) else { throw ToolError.invalid("Invalid note records") }
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        } catch { throw ToolError.unavailable("Sotto Notes could not be read. Existing data was preserved; no note was changed.") }
    }
    func get(_ id: String) throws -> SottoNote {
        guard let note = try all().first(where: { $0.id == id }) else { throw ToolError.invalid("Choose an actual Sotto note from notes.list or notes.search") }
        return note
    }
    private func persist(_ notes: [SottoNote]) throws {
        let parent = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try parent.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw ToolError.denied("Sotto Notes storage cannot be linked") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        let bytes = try JSONEncoder().encode(notes)
        guard bytes.count <= 10_000_000 else { throw ToolError.unavailable("Sotto Notes storage is full") }
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try Data(contentsOf: file) == bytes else { throw ToolError.unavailable("Note save could not be verified") }
    }
    static func validate(title: String, body: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              title.rangeOfCharacter(from: .controlCharacters) == nil, body.count <= 16_000, !body.contains("\0") else { throw ToolError.invalid("Use a note title of 1–200 characters and text up to 16000 characters") }
    }
    func create(title: String, body: String) throws -> SottoNote {
        try Self.validate(title: title, body: body); try Task.checkCancellation()
        var notes = try all()
        let exact = notes.filter { $0.title == title && $0.body == body }
        guard exact.count <= 1 else { throw ToolError.invalid("Several identical Sotto notes exist; choose an actual note") }
        if let existing = exact.first { return existing }
        guard notes.count < 500 else { throw ToolError.unavailable("Sotto Notes has reached its 500-note limit") }
        let note = SottoNote(id: UUID().uuidString, title: title, body: body, revision: 1, updatedAt: Date())
        notes.append(note); try persist(notes)
        return try get(note.id)
    }
    func update(id: String, revision: Int, title: String, body: String) throws -> SottoNote {
        try Self.validate(title: title, body: body); try Task.checkCancellation()
        var notes = try all()
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].revision == revision, revision < Int.max else { throw ToolError.denied("This Sotto note changed after review. Read it again before editing.") }
        notes[index].title = title; notes[index].body = body; notes[index].revision += 1; notes[index].updatedAt = Date()
        let updated = notes[index]; try persist(notes)
        return try get(updated.id)
    }
}
struct NotesTool: Tool {
    let action: String
    let store: SottoNoteStore
    init(action: String, store: SottoNoteStore = .shared) { self.action = action; self.store = store }
    var descriptor: ToolDescriptor {
        var properties: [String: JSONValue] = [:], required: [String] = []
        if action == "search" { properties["query"] = textProperty("Literal Sotto note title/body search"); required = ["query"] }
        if ["read", "update"].contains(action) { properties["id"] = textProperty("Actual Sotto Notes identifier"); required = ["id"] }
        if ["create", "update"].contains(action) {
            properties["title"] = textProperty("Sotto note title, not an Apple Notes title")
            properties["body"] = .object(["type": .string("string"), "maxLength": .number(16_000), "description": .string("Requested note text, up to 16000 characters")])
            required += action == "create" ? ["title", "body"] : []
        }
        if action == "update" {
            properties["revision"] = .object(["type": .string("integer")])
            properties["mode"] = textProperty("append requested text or replace with reviewed text", choices: ["append", "replace"])
            required += ["revision", "body", "mode"]
        }
        return ToolDescriptor(id: "notes." + action, description: "\(action.capitalized) Sotto-managed local notes, NOT Apple Notes. Always identify the source as Sotto Notes. Do not claim Apple Notes access or silently substitute this store when the user explicitly requests Apple Notes. Reads follow intelligence preferences. List/search actual IDs; updates require current revision and approval of the final content. No private Apple Notes database access.",
                              properties: properties, required: required, risk: ["create", "update"].contains(action) ? .consequential : .read, capabilities: [.notes])
    }
    private func revision(_ args: JSONValue) throws -> Int {
        guard case .number(let n) = args.object?["revision"], n >= 1, n < Double(Int.max), n.rounded() == n else { throw ToolError.invalid("Use the actual note revision") }
        return Int(n)
    }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        try descriptor.validate(arguments)
        guard action == "create" || action == "update" else { return arguments }
        var title = arguments.object?["title"]?.string ?? "", body = arguments.object?["body"]?.string ?? ""
        if action == "update" {
            let current = try await store.get(arguments.object?["id"]?.string ?? "")
            guard current.revision == (try revision(arguments)) else { throw ToolError.denied("This note changed. Read it again before editing.") }
            title = arguments.object?["title"]?.string ?? current.title
            if arguments.object?["mode"]?.string == "append" { body = current.body + (current.body.isEmpty ? "" : "\n") + body }
            try SottoNoteStore.validate(title: title, body: body)
            return .object(["id": .string(current.id), "revision": .number(Double(current.revision)), "title": .string(title), "body": .string(body), "mode": .string("replace")])
        }
        try SottoNoteStore.validate(title: title, body: body)
        return .object(["title": .string(title), "body": .string(body)])
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        if action == "list" || action == "search" {
            let query = arguments.object?["query"]?.string ?? ""
            guard query.count <= 200, action != "search" || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.invalid("Say which Sotto note to find") }
            let all = try await store.all()
            let matches = all.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
            return ToolResult("Found \(min(30, matches.count)) Sotto Notes results. These are Sotto-managed notes, not Apple Notes.",
                              data: .object(["source": .string("Sotto Notes"), "notes": .array(matches.prefix(30).map(\.reference)), "limited": .bool(matches.count > 30), "requires_disambiguation": .bool(!query.isEmpty && matches.count > 1), "untrusted": .bool(true)]))
        }
        if action == "read" {
            let note = try await store.get(arguments.object?["id"]?.string ?? "")
            return ToolResult("Read Sotto note “\(note.title)”", data: note.data)
        }
        let title = arguments.object?["title"]?.string ?? "", body = arguments.object?["body"]?.string ?? ""
        let note: SottoNote
        if action == "create" { note = try await store.create(title: title, body: body) }
        else {
            guard arguments.object?["mode"]?.string == "replace" else { throw ToolError.denied("Review the final note content before appending") }
            note = try await store.update(id: arguments.object?["id"]?.string ?? "", revision: revision(arguments), title: title, body: body)
        }
        return ToolResult("Saved Sotto note “\(note.title)” and verified its local contents. This is not an Apple Notes document.", data: note.data)
    }
}
