import Foundation
import SottoTools

struct AppleMailTool: Tool {
    let action: String
    let access: any AppleMailAccess
    let references: MailReferenceStore
    init(action: String, access: any AppleMailAccess = NativeAppleMailAccess.shared, references: MailReferenceStore = .shared) {
        self.action = action; self.access = access; self.references = references
    }
    var descriptor: ToolDescriptor {
        var p: [String: JSONValue] = [:], required: [String] = []
        if action == "search" {
            p = ["query": textProperty("Literal phrase in sender or subject; optional, up to 200 characters"),
                 "account_id": textProperty("Actual enabled account ID from mail.accounts; omit for all accessible inbox accounts"),
                 "after": textProperty("Inclusive ISO8601 received time, with seconds/time zone; optional"),
                 "before": textProperty("Exclusive ISO8601 received time, with seconds/time zone; optional"),
                 "unread_only": .object(["type": .string("boolean")])]
        }
        if action == "read" { p["message_ref"] = textProperty("Actual unexpired message_ref returned by mail.search, never an invented ID"); required = ["message_ref"] }
        let description: String = switch action {
        case "accounts": "List the accounts configured in Apple Mail. Uses macOS Automation; no account passwords or private databases are read."
        case "search": "Find inbox messages by sender, subject, date or unread status. Inspects at most 200 messages and returns up to 20. Other folders, body search and a guarantee of the newest message are outside this search."
        default: "Read the selected Apple Mail message as a text excerpt. Attachments and visual layout are excluded. The message must still match the account and inbox result you selected."
        }
        return ToolDescriptor(id: "mail." + action, description: description, properties: p, required: required, risk: .read, capabilities: [.mail, .automation], permissions: ["Automation access to Apple Mail; selected intelligence processing preferences"],
                              verification: "Validate actual account/native/RFC message identity before and after reading. No delivery, mailbox mutation or account synchronization is claimed.")
    }
    func authorizationArguments(_ args: JSONValue) async throws -> JSONValue {
        try descriptor.validate(args)
        if action == "search" { _ = try MailSearchRequest(args) }
        if action == "read" { _ = try await references.resolve(args.object?["message_ref"]?.string ?? "") }
        return args
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        if action == "accounts" {
            let result = try await access.accounts()
            guard case .array(let rows) = result.object?["accounts"], rows.count <= 10,
                  case .bool(let limited) = result.object?["limited"] else { throw ToolError.unavailable("Apple Mail returned an invalid account list.") }
            for row in rows {
                guard let id = row.object?["id"]?.string, !id.isEmpty, id.utf8.count <= 1000,
                      let name = row.object?["name"]?.string, name.utf8.count <= 1000, case .bool = row.object?["enabled"],
                      case .array(let addresses) = row.object?["addresses"], addresses.count <= 10,
                      addresses.allSatisfy({ $0.string != nil && $0.string!.utf8.count <= 1000 }) else { throw ToolError.unavailable("Apple Mail returned invalid account details.") }
            }
            // Project only reviewed fields. Never forward extra adapter data.
            let accounts = rows.map { row in JSONValue.object((row.object ?? [:]).filter { ["id", "name", "enabled", "addresses"].contains($0.key) }) }
            let enabled = accounts.contains { $0.object?["enabled"] == .bool(true) }
            return ToolResult(enabled ? "Apple Mail accounts. Choose a specific account only when the request identifies one." : "No enabled Apple Mail account was returned. Add or enable an account in Apple Mail to continue.",
                              data: .object(["source": .string("Apple Mail"), "accounts": .array(accounts), "limited": .bool(limited), "untrusted": .bool(true)]), state: enabled ? .success : .clarificationRequired)
        }
        if action == "search" {
            let request = try MailSearchRequest(arguments)
            let result = try await access.search(request)
            guard case .array(let rows) = result.object?["messages"], rows.count <= 20,
                  case .bool(let limited) = result.object?["limited"],
                  case .number(let scanned) = result.object?["inspected"], scanned >= 0, scanned <= 200, scanned.rounded() == scanned,
                  case .number(let skipped) = result.object?["skipped"], skipped >= 0, skipped <= scanned, skipped.rounded() == skipped else { throw ToolError.unavailable("Apple Mail returned an invalid search result.") }
            let identities = try rows.map(MailMessageIdentity.init)
            guard Set(identities.map { "\($0.accountID)\0\($0.nativeID)" }).count == identities.count else { throw ToolError.unavailable("Apple Mail returned duplicate message identities.") }
            var messages: [JSONValue] = []
            for identity in identities.sorted(by: { $0.receivedDate > $1.receivedDate }) {
                guard request.accountID.isEmpty || identity.accountID == request.accountID else { throw ToolError.denied("The Mail result did not match the requested account.") }
                var fields = identity.fields
                fields["message_ref"] = .string(await references.reference(identity))
                messages.append(.object(fields))
            }
            return ToolResult("Found \(messages.count) inbox messages in a bounded sender/subject search. This is not a complete mailbox search or a guarantee of the newest message.",
                              data: .object(["source": .string("Apple Mail"), "messages": .array(messages), "inspected": .number(scanned), "skipped": .number(skipped), "limited": .bool(limited || skipped > 0),
                                             "requires_disambiguation": .bool(messages.count > 1), "coverage": .string("First 200 accessible inbox messages; at most 20 matches, sorted within returned results. Other folders, attachments and message bodies are not searched."), "untrusted": .bool(true)]),
                              state: skipped > 0 ? .partiallyCompleted : .success)
        }
        let ref = arguments.object?["message_ref"]?.string ?? ""
        let identity = try await references.resolve(ref)
        let result = try await access.read(identity)
        guard result.identity.matches(identity) else { throw ToolError.denied("The selected Mail message changed. Search again.") }
        var data = result.identity.fields
        data["message_ref"] = .string(ref); data["text"] = .string(result.text); data["partial"] = .bool(result.partial)
        data["read_status_changed"] = .bool(result.readStatusChanged); data["source"] = .string("Apple Mail"); data["untrusted"] = .bool(true)
        data["coverage"] = .string("Text excerpt up to 16000 UTF-8 bytes. Attachments, rich layout, complete threads and remote visual resources are not read.")
        return ToolResult(result.readStatusChanged ? "Read a text excerpt, but Mail's read status changed during the read. No explicit mailbox update was requested." : result.partial ? "Read a partial Apple Mail text excerpt; the rest was omitted." : "Read Apple Mail message text; attachments and visual layout are excluded.",
                          data: .object(data), state: result.readStatusChanged ? .partiallyCompleted : .success)
    }
}
