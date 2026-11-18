import Foundation
import CryptoKit
import SottoTools

struct AppleNoteSnapshot: Sendable {
    let id: String, title: String, html: String, text: String, folder: String
    let shared: Bool
    let attachments: Int
    var revision: String { SHA256.hash(data: Data((id + "\0" + title + "\0" + html + "\0" + String(shared) + String(attachments)).utf8)).map { String(format: "%02x", $0) }.joined() }
    var data: JSONValue { .object(["id": .string(id), "title": .string(title), "text": .string(text), "folder": .string(folder), "revision": .string(revision),
                                  "source": .string("Apple Notes"), "shared": .bool(shared), "attachments": .number(Double(attachments)), "untrusted": .bool(true),
                                  "coverage": .string("Plaintext of a bounded Apple Note. Attachments and rich visual layout are not read.")]) }
    init(_ value: JSONValue) throws {
        guard let row = value.object, let id = row["id"]?.string, !id.isEmpty, id.count <= 2048,
              let title = row["title"]?.string, title.utf8.count <= 1000,
              let html = row["html"]?.string, html.utf8.count <= 24_000, let text = row["text"]?.string, text.utf8.count <= 24_000,
              let folder = row["folder"]?.string, folder.count <= 1000,
              case .bool(let shared) = row["shared"], case .number(let attachments) = row["attachments"], attachments >= 0, attachments <= 10_000, attachments.rounded() == attachments else { throw ToolError.unavailable("Apple Notes returned invalid or oversized note data") }
        self.id = id; self.title = title; self.html = html; self.text = text; self.folder = folder; self.shared = shared; self.attachments = Int(attachments)
    }
}
protocol AppleNotesAccess: Sendable {
    func list(query: String) async throws -> JSONValue
    func destination(_ id: String) async throws -> (id: String, name: String)
    func read(_ id: String) async throws -> AppleNoteSnapshot
    func create(folder: String, title: String, html: String) async throws -> AppleNoteSnapshot
    func update(_ note: AppleNoteSnapshot, html: String) async throws -> AppleNoteSnapshot
}
actor NativeAppleNotesAccess: AppleNotesAccess {
    static let shared = NativeAppleNotesAccess()
    private var attemptedCreations: Set<String> = []
    private func call(_ arguments: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        guard AppleNotesAuthorization.status() == .allowed else { throw ToolError.denied("Connect Apple Notes through Sotto before accessing notes.") }
        let bytes = try JSONEncoder().encode(JSONValue.object(arguments))
        let output = try await AppleScriptExecutor().executeReviewed(AppleNotesScript.source, input: bytes, targetName: "Apple Notes")
        guard let data = output.data(using: .utf8), data.count <= 65_536 else { throw ToolError.unavailable("Apple Notes output exceeded its limit") }
        try Task.checkCancellation()
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    func list(query: String) async throws -> JSONValue {
        let result = try await call(["action": .string(query.isEmpty ? "list" : "search"), "query": .string(query)])
        guard case .array(let rows) = result.object?["notes"], rows.count <= 20,
              rows.allSatisfy({ ($0.object?["id"]?.string?.count ?? 0) > 0 && ($0.object?["title"]?.string?.utf8.count ?? Int.max) <= 1000 }) else { throw ToolError.unavailable("Invalid Apple Notes result list") }
        return .object((result.object ?? [:]).merging(["source": .string("Apple Notes"), "untrusted": .bool(true), "requires_disambiguation": .bool(!query.isEmpty && rows.count > 1)]) { _, new in new })
    }
    func destination(_ id: String) async throws -> (id: String, name: String) {
        let value = try await call(["action": .string("destination"), "folder_id": .string(id)])
        guard let id = value.object?["id"]?.string, !id.isEmpty, id.count <= 2048, let name = value.object?["name"]?.string, name.count <= 500 else { throw ToolError.unavailable("Apple Notes has no supported writable destination") }
        return (id, name)
    }
    func read(_ id: String) async throws -> AppleNoteSnapshot {
        guard !id.isEmpty, id.count <= 2048 else { throw ToolError.invalid("Choose an actual Apple Note identifier.") }
        let note = try await AppleNoteSnapshot(call(["action": .string("read"), "id": .string(id)]))
        guard note.id == id else { throw ToolError.unavailable("Apple Notes returned a different note; nothing further was changed.") }
        return note
    }
    func create(folder: String, title: String, html: String) async throws -> AppleNoteSnapshot {
        let intent = folder + "\0" + html
        guard attemptedCreations.count < 100, attemptedCreations.insert(intent).inserted else { throw ToolError.denied("This Apple Notes creation was already attempted. Check Notes before retrying; it will not be repeated automatically.") }
        return try await AppleNoteSnapshot(call(["action": .string("create"), "folder_id": .string(folder), "title": .string(title), "html": .string(html)]))
    }
    func update(_ note: AppleNoteSnapshot, html: String) async throws -> AppleNoteSnapshot {
        try await AppleNoteSnapshot(call(["action": .string("update"), "id": .string(note.id), "expected_html": .string(note.html), "expected_title": .string(note.title), "html": .string(html)]))
    }
}
enum AppleNotesText {
    static func validate(title: String, body: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              title.rangeOfCharacter(from: .controlCharacters) == nil, body.utf8.count <= 12_000, !body.contains("\0") else { throw ToolError.invalid("Use a title of 1–200 characters and note text up to 12000 UTF-8 bytes") }
    }
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    static func fragment(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").map { "<div>" + ($0.isEmpty ? "<br>" : escape($0)) + "</div>" }.joined()
    }
    static func document(title: String, body: String) -> String { "<div><b>" + escape(title) + "</b></div>" + fragment(body) }
    static func appending(_ text: String, to html: String) throws -> String {
        let addition = fragment(text)
        var result = html
        if let range = result.range(of: "</body>", options: [.caseInsensitive, .backwards]) { result.insert(contentsOf: addition, at: range.lowerBound) }
        else if result.range(of: "</html>", options: .caseInsensitive) != nil { throw ToolError.denied("This note's layout cannot be safely appended. Review it in Apple Notes.") }
        else { result += addition }
        guard result.utf8.count <= 24_000 else { throw ToolError.invalid("The updated Apple Note exceeds the safe size limit") }
        return result
    }
    static func normalized(_ text: String) -> String { text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n") }
}
