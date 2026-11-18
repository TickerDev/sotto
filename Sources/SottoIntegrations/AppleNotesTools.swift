import Foundation
import SottoTools

struct AppleNotesTool: Tool {
    let action: String
    let access: any AppleNotesAccess
    init(action: String, access: any AppleNotesAccess = NativeAppleNotesAccess.shared) { self.action = action; self.access = access }
    var requiresPermissionForAuthorization: Bool { ["create", "update"].contains(action) }
    var descriptor: ToolDescriptor {
        var p: [String: JSONValue] = [:], required: [String] = []
        let body: JSONValue = .object(["type": .string("string"), "maxLength": .number(16_000), "description": .string("Requested text; update approval expands this to the final visible note text.")])
        if action == "search" { p["query"] = textProperty("Literal title search, up to 200 characters"); required = ["query"] }
        if ["read", "update"].contains(action) { p["id"] = textProperty("Actual Apple Notes identifier from a result"); required = ["id"] }
        if ["create", "update"].contains(action) {
            p["title"] = textProperty("Title; updates retain the actual existing title")
            p["body"] = body
            p["folder_name"] = textProperty("Resolved destination for review")
            required += ["body"]
        }
        if action == "create" { p["folder_id"] = textProperty("Actual destination folder ID; omit for the default Notes folder"); required += ["title"] }
        if action == "update" {
            p["revision"] = textProperty("Actual revision from appleNotes.read"); p["mode"] = textProperty("Append text or replace existing text; replacement removes rich formatting", choices: ["append", "replace"])
            p["addition"] = body
            required += ["revision", "mode"]
        }
        return ToolDescriptor(id: "appleNotes." + action, description: "\(action.capitalized) Apple Notes through its public Automation interface. Separate from notes.* (Sotto Notes). Title-only search inspects at most 200 notes and returns at most 20; not full-content search or newest-first. Bounded plaintext reads exclude attachments. Changes require review and current revision; locked, shared and attachment-bearing notes cannot be edited. Replace removes rich formatting. Never read a private Notes database.",
                              properties: p, required: required, risk: requiresPermissionForAuthorization ? .consequential : .read, capabilities: [.notes, .automation],
                              permissions: ["Automation access to Apple Notes"], verification: "Re-read actual note ID, title and normalized visible plaintext after mutation. Rich visual layout and cloud synchronization are not verified.")
    }
    private func value(_ args: JSONValue, _ key: String) -> String { args.object?[key]?.string ?? "" }
    private func editable(_ note: AppleNoteSnapshot) throws {
        guard !note.shared, note.attachments == 0 else { throw ToolError.denied("Shared notes or notes with attachments must be edited in Apple Notes.") }
    }
    private func bounded(_ html: String) throws {
        guard html.utf8.count <= 24_000 else { throw ToolError.invalid("The encoded note exceeds the safe Apple Notes size limit.") }
    }
    func authorizationArguments(_ args: JSONValue) async throws -> JSONValue {
        try descriptor.validate(args)
        if action == "create" {
            let title = value(args, "title"), body = value(args, "body")
            try AppleNotesText.validate(title: title, body: body)
            try bounded(AppleNotesText.document(title: title, body: body))
            let folder = try await access.destination(value(args, "folder_id"))
            return .object(["title": .string(title), "body": .string(body), "folder_id": .string(folder.id), "folder_name": .string(folder.name)])
        }
        if action == "update" {
            let note = try await access.read(value(args, "id"))
            try editable(note)
            guard note.revision == value(args, "revision") else { throw ToolError.denied("This Apple Note changed. Read it again before editing.") }
            let requested = value(args, "body"), mode = value(args, "mode")
            try AppleNotesText.validate(title: note.title, body: requested)
            let final = mode == "append" ? note.text + "\n" + requested : note.title + "\n" + requested
            guard final.count <= 16_000, final.utf8.count <= 24_000 else { throw ToolError.invalid("The final note exceeds the review limit.") }
            let html = mode == "append" ? try AppleNotesText.appending(requested, to: note.html) : AppleNotesText.document(title: note.title, body: requested)
            try bounded(html)
            return .object(["id": .string(note.id), "revision": .string(note.revision), "title": .string(note.title), "body": .string(final),
                            "addition": .string(requested), "mode": .string(mode), "folder_name": .string(note.folder)])
        }
        return args
    }
    func execute(arguments args: JSONValue) async throws -> ToolResult {
        try descriptor.validate(args); try Task.checkCancellation()
        if action == "list" || action == "search" {
            let query = value(args, "query")
            guard query.count <= 200, action != "search" || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.invalid("Say which Apple Note title to find.") }
            return ToolResult("Apple Notes title results. Search is bounded and does not read note bodies.", data: try await access.list(query: query))
        }
        if action == "read" {
            return ToolResult("Read Apple Notes plaintext. Attachments and visual layout are excluded.", data: try await access.read(value(args, "id")).data)
        }
        let expected: String, saved: AppleNoteSnapshot, expectedID: String?
        if action == "create" {
            let title = value(args, "title"), body = value(args, "body")
            try AppleNotesText.validate(title: title, body: body)
            let folder = try await access.destination(value(args, "folder_id"))
            guard !value(args, "folder_id").isEmpty, folder.id == value(args, "folder_id"), folder.name == value(args, "folder_name") else { throw ToolError.denied("Review the actual Apple Notes destination before creating.") }
            let html = AppleNotesText.document(title: title, body: body); try bounded(html)
            expected = title + "\n" + body; expectedID = nil
            saved = try await access.create(folder: folder.id, title: title, html: html)
        } else {
            let note = try await access.read(value(args, "id")); try editable(note)
            guard note.revision == value(args, "revision"), note.title == value(args, "title"), let addition = args.object?["addition"]?.string else { throw ToolError.denied("This note changed or the final text was not reviewed. Read it again before editing.") }
            try AppleNotesText.validate(title: note.title, body: addition)
            let mode = value(args, "mode")
            expected = mode == "append" ? note.text + "\n" + addition : note.title + "\n" + addition
            guard expected == value(args, "body") else { throw ToolError.denied("The approved final text does not match this update.") }
            let html = mode == "append" ? try AppleNotesText.appending(addition, to: note.html) : AppleNotesText.document(title: note.title, body: addition)
            try bounded(html); expectedID = note.id
            saved = try await access.update(note, html: html)
        }
        let verified: AppleNoteSnapshot
        do { verified = try await access.read(saved.id) }
        catch is CancellationError { throw CancellationError() }
        catch {
            return ToolResult("Apple Notes accepted a change, but the note could not be read back. Check it before retrying.",
                              data: .object(["id": .string(saved.id), "source": .string("Apple Notes"), "untrusted": .bool(true)]), state: .partiallyCompleted)
        }
        guard (expectedID == nil || verified.id == expectedID), verified.title == value(args, "title"),
              AppleNotesText.normalized(verified.text) == AppleNotesText.normalized(expected), !verified.shared, verified.attachments == 0 else {
            return ToolResult("Apple Notes accepted a change, but its final text could not be verified. Check the note before retrying.", data: verified.data, state: .partiallyCompleted)
        }
        return ToolResult("Saved the Apple Note and verified its visible text.", data: verified.data)
    }
}
