import Foundation
import CryptoKit
import Darwin
import SottoTools

struct MailDraftRequest: Sendable {
    let accountID: String, sender: String, subject: String, body: String
    let to: [String]
    static func address(_ value: String) -> Bool {
        value.utf8.count <= 254 && value.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_{}|~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"#, options: .regularExpression) != nil
    }
    init(_ args: JSONValue) throws {
        guard let account = args.object?["account_id"]?.string, !account.isEmpty, account.utf8.count <= 1000,
              let sender = args.object?["sender"]?.string, Self.address(sender),
              let subject = args.object?["subject"]?.string, !subject.trimmingCharacters(in: .whitespaces).isEmpty, subject.count <= 200, subject.rangeOfCharacter(from: .controlCharacters) == nil,
              let body = args.object?["body"]?.string, body.utf8.count <= 12_000, !body.contains("\0"),
              case .array(let rows) = args.object?["to"], (1...10).contains(rows.count),
              rows.allSatisfy({ $0.string.map(Self.address) == true }) else { throw ToolError.invalid("Choose an actual Mail account, a sender address, 1–10 plain recipient addresses, a short subject and text up to 12000 UTF-8 bytes.") }
        to = rows.compactMap(\.string)
        guard Set(to.map { $0.lowercased() }).count == to.count else { throw ToolError.invalid("Remove duplicate recipients before reviewing the draft.") }
        accountID = account; self.sender = sender; self.subject = subject; self.body = body
    }
    var fields: [String: JSONValue] { ["account_id": .string(accountID), "sender": .string(sender), "to": .array(to.map(JSONValue.string)), "subject": .string(subject), "body": .string(body)] }
    var fingerprint: String { SHA256.hash(data: Data(JSONValue.object(fields).encoded.utf8)).map { String(format: "%02x", $0) }.joined() }
}
protocol MailDraftAccess: Sendable {
    func accounts() async throws -> JSONValue
    func create(_ request: MailDraftRequest) async throws -> JSONValue
    func read(_ id: Int) async throws -> JSONValue
}
actor NativeMailDraftAccess: MailDraftAccess {
    static let shared = NativeMailDraftAccess()
    func accounts() async throws -> JSONValue { try await NativeAppleMailAccess.shared.accounts() }
    private func call(_ args: [String: JSONValue]) async throws -> JSONValue {
        try Task.checkCancellation()
        guard AppleMailAuthorization.status() == .allowed else { throw ToolError.denied("Connect Apple Mail before preparing a draft.") }
        let output = try await AppleScriptExecutor().executeReviewed(MailDraftScript.source, input: JSONEncoder().encode(JSONValue.object(args)), targetName: "Apple Mail", timeout: 25)
        try Task.checkCancellation()
        return try JSONDecoder().decode(JSONValue.self, from: Data(output.utf8))
    }
    func create(_ request: MailDraftRequest) async throws -> JSONValue { try await call(request.fields.merging(["action": .string("create")]) { _, new in new }) }
    func read(_ id: Int) async throws -> JSONValue { try await call(["action": .string("read"), "native_id": .number(Double(id))]) }
}
/// Only hashes are persisted, never recipients or message bodies. A reservation
/// precedes native dispatch and is never cleared automatically on uncertainty.
actor MailDraftJournal {
    static let shared = MailDraftJournal()
    private let file: URL
    init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sotto/Mail/draft-attempts.json")) { self.file = file }
    func reserve(_ fingerprint: String) throws -> Bool {
        guard fingerprint.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { throw ToolError.invalid("Invalid draft receipt.") }
        let parent = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ToolError.denied("Linked draft receipt storage is unsupported.") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        let lock = Darwin.open(file.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw ToolError.unavailable("Draft receipt locking is unavailable.") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lock); throw ToolError.unavailable("Another draft reservation is in progress. No draft was created.") }
        defer { _ = flock(lock, LOCK_UN); Darwin.close(lock) }
        var attempts: Set<String> = []
        if FileManager.default.fileExists(atPath: file.path) {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 100_000 else { throw ToolError.unavailable("Draft receipts cannot be safely read. Existing data was preserved.") }
            attempts = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: file))
            guard attempts.count <= 1000, attempts.allSatisfy({ $0.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil }) else { throw ToolError.unavailable("Invalid draft receipts. Existing data was preserved.") }
        }
        if attempts.contains(fingerprint) { return false }
        guard attempts.count < 1000 else { throw ToolError.unavailable("Draft receipt storage is full. No draft was created.") }
        try Task.checkCancellation()
        attempts.insert(fingerprint)
        let data = try JSONEncoder().encode(attempts)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        try handle.synchronize()
        guard try Data(contentsOf: file) == data else { throw ToolError.unavailable("Draft receipt persistence could not be verified.") }
        return true
    }
}
struct MailDraftTool: Tool {
    let access: any MailDraftAccess
    let journal: MailDraftJournal
    init(access: any MailDraftAccess = NativeMailDraftAccess.shared, journal: MailDraftJournal = .shared) { self.access = access; self.journal = journal }
    var requiresPermissionForAuthorization: Bool { true }
    var descriptor: ToolDescriptor {
        ToolDescriptor(id: "mail.draft", description: "Prepare a new unsent message in Apple Mail after reviewing sender, recipients, subject and complete text. This opens a compose window; saved Drafts-folder persistence and delivery are not promised. Sending, replies, attachments, CC and BCC are unavailable. Identical attempts are not automatically repeated, even after relaunch.",
                       properties: ["account_id": textProperty("Actual enabled account from mail.accounts"), "account_name": textProperty("Native account name for review"),
                                    "sender": textProperty("A plain sender address configured on that account"), "to": .object(["type": .string("array"), "items": textProperty("Plain recipient email address")]),
                                    "subject": textProperty("Subject, 1–200 characters"), "body": .object(["type": .string("string"), "maxLength": .number(12_000)])],
                       required: ["account_id", "sender", "to", "subject", "body"], risk: .consequential, capabilities: [.mail, .automation],
                       permissions: ["Apple Mail Automation; review of sender, recipients, subject and complete body"], verification: "Independent outgoing-message lookup compares actual ID, sender, recipients, subject and text. No send or cloud-save verification.")
    }
    private func account(_ request: MailDraftRequest) async throws -> String {
        let result = try await access.accounts()
        guard case .array(let accounts) = result.object?["accounts"],
              let account = accounts.first(where: { $0.object?["id"]?.string == request.accountID && $0.object?["enabled"] == .bool(true) }),
              case .array(let addresses) = account.object?["addresses"],
              addresses.contains(where: { $0.string?.caseInsensitiveCompare(request.sender) == .orderedSame }),
              let name = account.object?["name"]?.string, name.count <= 1000 else { throw ToolError.denied("Choose an enabled Mail account and one of its actual sender addresses.") }
        return name
    }
    func authorizationArguments(_ args: JSONValue) async throws -> JSONValue {
        try descriptor.validate(args)
        let request = try MailDraftRequest(args)
        var fields = request.fields
        fields["account_name"] = .string(try await account(request))
        return .object(fields)
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let request = try MailDraftRequest(arguments)
        guard try await account(request) == arguments.object?["account_name"]?.string else { throw ToolError.denied("The sender account changed. Review this draft again.") }
        try Task.checkCancellation()
        guard try await journal.reserve(request.fingerprint) else {
            return ToolResult("This exact draft was already attempted. Check Apple Mail before creating another; it was not repeated.", data: .object(["source": .string("Apple Mail"), "send_requested": .bool(false)]), state: .partiallyCompleted)
        }
        var id: Int?
        do {
            let created = try await access.create(request)
            guard case .number(let n) = created.object?["native_id"], n >= 1, n <= 2_147_483_647, n.rounded() == n else { throw ToolError.unavailable("No actual draft identifier.") }
            id = Int(n)
            let result = try await access.read(Int(n))
            guard result.object?["native_id"] == .number(n),
                  result.object?["sender"]?.string?.caseInsensitiveCompare(request.sender) == .orderedSame,
                  result.object?["subject"]?.string == request.subject,
                  result.object?["body"]?.string == request.body,
                  case .array(let to) = result.object?["to"], to.count == request.to.count, to.allSatisfy({ $0.string != nil }), to.compactMap(\.string).map({ $0.lowercased() }).sorted() == request.to.map({ $0.lowercased() }).sorted(),
                  result.object?["cc_count"] == .number(0), result.object?["bcc_count"] == .number(0),
                  result.object?["visible"] == .bool(true) else { throw ToolError.unavailable("Draft fields differ from review.") }
            return ToolResult("Prepared an unsent message in Apple Mail and verified its fields. Review it in Mail; saved Drafts-folder persistence is not verified.",
                              data: .object(["native_id": .number(n), "source": .string("Apple Mail"), "send_requested": .bool(false), "verified": .bool(true)]))
        } catch is CancellationError { throw CancellationError() }
        catch {
            var fields: [String: JSONValue] = ["source": .string("Apple Mail"), "send_requested": .bool(false), "verified": .bool(false)]
            if let id { fields["native_id"] = .number(Double(id)) }
            return ToolResult("Draft preparation could not be verified. A complete or incomplete compose window may exist in Apple Mail. Check it before retrying; Sotto will not repeat this attempt automatically.", data: .object(fields), state: .partiallyCompleted)
        }
    }
}
