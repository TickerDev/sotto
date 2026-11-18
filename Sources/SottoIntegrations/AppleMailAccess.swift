import Foundation
import SottoTools

enum MailTimestamp {
    /// Foundation accepts some impossible dates/offsets by normalizing them.
    /// Require a round trip in the requested offset before touching account data.
    static func date(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        let suffix = String(value.dropFirst(19))
        let offset: Int
        if suffix == "Z" { offset = 0 }
        else {
            let fields = suffix.dropFirst().split(separator: ":")
            guard fields.count == 2, let hours = Int(fields[0]), let minutes = Int(fields[1]), hours <= 23, minutes <= 59 else { return nil }
            offset = (hours * 3600 + minutes * 60) * (suffix.hasPrefix("-") ? -1 : 1)
        }
        guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = zone
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == String(value.prefix(19)) + (offset == 0 ? "Z" : suffix) else { return nil }
        return date
    }
}
struct MailSearchRequest: Sendable {
    let query: String, accountID: String, after: String, before: String
    let unreadOnly: Bool
    init(_ args: JSONValue) throws {
        query = args.object?["query"]?.string ?? ""
        accountID = args.object?["account_id"]?.string ?? ""
        after = args.object?["after"]?.string ?? ""
        before = args.object?["before"]?.string ?? ""
        if case .bool(let value) = args.object?["unread_only"] { unreadOnly = value } else { unreadOnly = false }
        guard query.count <= 200, accountID.utf8.count <= 1000, ![query, accountID, after, before].contains(where: { $0.contains("\0") }) else { throw ToolError.invalid("Use a short sender or subject phrase and an actual Mail account.") }
        func date(_ value: String) throws -> Date? {
            if value.isEmpty { return nil }
            guard let d = MailTimestamp.date(value) else { throw ToolError.invalid("Use valid Mail dates with seconds and a time zone.") }
            return d
        }
        let start = try date(after), end = try date(before)
        if let start, let end, end <= start { throw ToolError.invalid("The end of the Mail date range must be after its start.") }
    }
    var arguments: [String: JSONValue] {
        ["action": .string("search"), "query": .string(query), "account_id": .string(accountID), "after": .string(after), "before": .string(before), "unread_only": .bool(unreadOnly)]
    }
}
struct MailMessageIdentity: Sendable, Equatable {
    let nativeID: Int
    let accountID: String, rfcID: String, subject: String, sender: String, receivedAt: String, mailbox: String, accountName: String
    let isRead: Bool
    let receivedDate: Date
    init(_ row: JSONValue) throws {
        guard case .number(let n) = row.object?["native_id"], n >= 1, n <= 2_147_483_647, n.rounded() == n,
              let accountID = row.object?["account_id"]?.string, !accountID.isEmpty, accountID.utf8.count <= 1000,
              let rfc = row.object?["rfc_message_id"]?.string, rfc.utf8.count <= 1000,
              let subject = row.object?["subject"]?.string, subject.utf8.count <= 2000,
              let sender = row.object?["sender"]?.string, sender.utf8.count <= 2000,
              let date = row.object?["received_at"]?.string, date.utf8.count <= 40, let receivedDate = MailTimestamp.date(date),
              let box = row.object?["mailbox"]?.string, !box.isEmpty, box.utf8.count <= 1000,
              let name = row.object?["account_name"]?.string, name.utf8.count <= 1000,
              case .bool(let read) = row.object?["is_read"] else { throw ToolError.unavailable("Apple Mail returned an invalid message reference.") }
        nativeID = Int(n); self.accountID = accountID; rfcID = rfc; self.subject = subject; self.sender = sender; receivedAt = date; mailbox = box; accountName = name; isRead = read; self.receivedDate = receivedDate
    }
    /// A read-status change does not retarget a message; all identity and
    /// displayed selection fields must still agree.
    func matches(_ other: Self) -> Bool {
        nativeID == other.nativeID && accountID == other.accountID && rfcID == other.rfcID &&
        subject == other.subject && sender == other.sender && receivedAt == other.receivedAt && mailbox == other.mailbox
    }
    var fields: [String: JSONValue] {
        ["native_id": .number(Double(nativeID)), "account_id": .string(accountID), "rfc_message_id": .string(rfcID), "subject": .string(subject),
         "sender": .string(sender), "received_at": .string(receivedAt), "mailbox": .string(mailbox), "account_name": .string(accountName), "is_read": .bool(isRead)]
    }
}
struct MailMessageText: Sendable {
    let identity: MailMessageIdentity
    let text: String
    let partial: Bool, readStatusChanged: Bool
    init(_ row: JSONValue) throws {
        identity = try MailMessageIdentity(row)
        guard let text = row.object?["text"]?.string, text.utf8.count <= 16_000,
              case .bool(let partial) = row.object?["partial"], case .bool(let changed) = row.object?["read_status_changed"] else { throw ToolError.unavailable("Apple Mail returned invalid or oversized message text.") }
        self.text = text; self.partial = partial; readStatusChanged = changed
    }
}
protocol AppleMailAccess: Sendable {
    func accounts() async throws -> JSONValue
    func search(_ request: MailSearchRequest) async throws -> JSONValue
    func read(_ identity: MailMessageIdentity) async throws -> MailMessageText
}
actor NativeAppleMailAccess: AppleMailAccess {
    static let shared = NativeAppleMailAccess()
    private func call(_ args: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        guard AppleMailAuthorization.status() == .allowed else { throw ToolError.denied("Connect Apple Mail through Sotto before reading email.") }
        let output: String
        do { output = try await AppleScriptExecutor().executeReviewed(AppleMailScript.source, input: try JSONEncoder().encode(JSONValue.object(args)), targetName: "Apple Mail", timeout: 25) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ToolError.unavailable("Apple Mail could not complete this read. Check its connection and Automation permission, then try again.") }
        try Task.checkCancellation()
        guard let data = output.data(using: .utf8), data.count <= 60_000 else { throw ToolError.unavailable("Apple Mail exceeded its output limit.") }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    func accounts() async throws -> JSONValue { try await call(["action": .string("accounts")]) }
    func search(_ request: MailSearchRequest) async throws -> JSONValue {
        let result = try await accounts()
        guard case .array(let rows) = result.object?["accounts"], rows.contains(where: { $0.object?["enabled"] == .bool(true) }) else {
            throw ToolError.unavailable("No enabled Apple Mail account is available. Add or enable one in Apple Mail before searching.")
        }
        if !request.accountID.isEmpty {
            guard rows.contains(where: { $0.object?["id"]?.string == request.accountID && $0.object?["enabled"] == .bool(true) }) else { throw ToolError.invalid("Choose an enabled account returned by mail.accounts.") }
        }
        return try await call(request.arguments)
    }
    func read(_ identity: MailMessageIdentity) async throws -> MailMessageText {
        let value = try await call(identity.fields.merging(["action": .string("read")]) { _, new in new })
        let result = try MailMessageText(value)
        guard result.identity.matches(identity) else { throw ToolError.denied("This Mail message changed. Search again before reading it.") }
        return result
    }
}
/// Session-local resource broker; models cannot invent a native message ID or
/// redirect a read into a different account/mailbox. Expiry requires discovery.
actor MailReferenceStore {
    static let shared = MailReferenceStore()
    private struct Entry { let identity: MailMessageIdentity; let expires: Date }
    private var entries: [String: Entry] = [:]
    private let lifetime: TimeInterval
    init(lifetime: TimeInterval = 600) { self.lifetime = lifetime }
    func reference(_ identity: MailMessageIdentity) -> String {
        let now = Date()
        entries = entries.filter { $0.value.expires > now }
        if let existing = entries.first(where: { $0.value.identity.matches(identity) }) { return existing.key }
        if entries.count >= 200, let oldest = entries.min(by: { $0.value.expires < $1.value.expires }) { entries.removeValue(forKey: oldest.key) }
        let id = UUID().uuidString
        entries[id] = Entry(identity: identity, expires: now.addingTimeInterval(lifetime))
        return id
    }
    func resolve(_ ref: String) throws -> MailMessageIdentity {
        guard UUID(uuidString: ref) != nil, let entry = entries[ref], entry.expires > Date() else {
            entries.removeValue(forKey: ref)
            throw ToolError.denied("This Mail result expired or is unavailable. Search again to select the actual message.")
        }
        return entry.identity
    }
}
