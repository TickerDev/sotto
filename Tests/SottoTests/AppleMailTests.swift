import XCTest
import SottoTools
@testable import SottoIntegrations

private func mailRow(id: Int = 42, account: String = "account-A", text: String? = nil, partial: Bool = false, changed: Bool = false) -> JSONValue {
    var fields: [String: JSONValue] = ["native_id": .number(Double(id)), "account_id": .string(account), "account_name": .string("Study"),
        "rfc_message_id": .string("<actual-id@example.test>"), "subject": .string("Internship"), "sender": .string("Professor <professor@example.test>"),
        "received_at": .string("2026-11-18T16:00:00Z"), "mailbox": .string("Inbox"), "is_read": .bool(false)]
    if let text { fields["text"] = .string(text); fields["partial"] = .bool(partial); fields["read_status_changed"] = .bool(changed) }
    return .object(fields)
}
private actor MailFixture: AppleMailAccess {
    var rows = [mailRow()]
    var readRow = mailRow(text: "Synthetic internship details.")
    var readCount = 0
    var skipped = 0
    var emptyAccounts = false
    func accounts() -> JSONValue {
        .object(["accounts": .array(emptyAccounts ? [] : [.object(["id": .string("account-A"), "name": .string("Study"), "enabled": .bool(true), "addresses": .array([.string("student@example.test")]), "unexpected_password": .string("MUST_NOT_RETURN")])]), "limited": .bool(false)])
    }
    func search(_ request: MailSearchRequest) -> JSONValue {
        .object(["messages": .array(rows), "limited": .bool(false), "inspected": .number(3), "skipped": .number(Double(skipped))])
    }
    func read(_ identity: MailMessageIdentity) throws -> MailMessageText { readCount += 1; return try MailMessageText(readRow) }
    func replaceRead(_ row: JSONValue) { readRow = row }
    func replaceSearch(_ values: [JSONValue], skipped: Int = 0) { rows = values; self.skipped = skipped }
    func clearAccounts() { emptyAccounts = true }
}

final class AppleMailTests: XCTestCase, @unchecked Sendable {
    private func reference(_ access: MailFixture, store: MailReferenceStore) async throws -> (String, ToolResult) {
        let result = try await AppleMailTool(action: "search", access: access, references: store).execute(arguments: .object(["query": .string("Internship")]))
        guard case .array(let rows) = result.data.object?["messages"], let ref = rows.first?.object?["message_ref"]?.string else { throw ToolError.invalid("No test reference") }
        return (ref, result)
    }
    func testAccountsProjectOnlySupportedFieldsAndNoAccountIsClarification() async throws {
        let access = MailFixture(), tool = AppleMailTool(action: "accounts", access: access)
        let result = try await tool.execute(arguments: .object([:]))
        XCTAssertEqual(result.state, .success)
        XCTAssertEqual(result.data.object?["source"], .string("Apple Mail"))
        XCTAssertFalse(result.data.encoded.contains("MUST_NOT_RETURN"))
        await access.clearAccounts()
        let empty = try await tool.execute(arguments: .object([:]))
        XCTAssertEqual(empty.state, .clarificationRequired)
    }
    func testSearchReferenceReadKeepsActualIdentityAndNeverSearchesBodies() async throws {
        let access = MailFixture(), store = MailReferenceStore()
        let (ref, search) = try await reference(access, store: store)
        XCTAssertFalse(search.data.encoded.contains("Synthetic internship details"))
        XCTAssertTrue(search.data.encoded.contains("<actual-id@example.test>"))
        XCTAssertTrue(search.summary.contains("bounded"))
        let tool = AppleMailTool(action: "read", access: access, references: store)
        let args: JSONValue = .object(["message_ref": .string(ref)])
        let approved = try await tool.authorizationArguments(args)
        let result = try await tool.execute(arguments: approved)
        XCTAssertEqual(result.state, .success)
        XCTAssertEqual(result.data.object?["native_id"], .number(42))
        XCTAssertEqual(result.data.object?["account_id"], .string("account-A"))
        XCTAssertEqual(result.data.object?["text"], .string("Synthetic internship details."))
        XCTAssertEqual(result.data.object?["untrusted"], .bool(true))
        XCTAssertEqual(result.data.object?["message_ref"], .string(ref))
    }
    func testFabricatedExpiredAndCrossSessionReferencesNeverDispatchReads() async throws {
        let access = MailFixture(), expired = MailReferenceStore(lifetime: -1)
        let (ref, _) = try await reference(access, store: expired)
        for (value, store) in [(ref, expired), (UUID().uuidString, MailReferenceStore()), ("42", MailReferenceStore())] {
            let tool = AppleMailTool(action: "read", access: access, references: store)
            do { _ = try await tool.execute(arguments: .object(["message_ref": .string(value)])); XCTFail("Must reject unresolved identity") } catch {}
        }
        let reads = await access.readCount; XCTAssertEqual(reads, 0)
    }
    func testChangedAccountNativeIDOrRFCIdentityCannotBeReadAsTheSelectedMessage() async throws {
        let access = MailFixture(), store = MailReferenceStore()
        let (ref, _) = try await reference(access, store: store)
        for row in [mailRow(account: "different", text: "Wrong account"), mailRow(id: 43, text: "Wrong message")] {
            await access.replaceRead(row)
            do { _ = try await AppleMailTool(action: "read", access: access, references: store).execute(arguments: .object(["message_ref": .string(ref)])); XCTFail() } catch {}
        }
        var changed = mailRow(text: "Wrong RFC identity").object!
        changed["rfc_message_id"] = .string("<other@example.test>")
        await access.replaceRead(.object(changed))
        do { _ = try await AppleMailTool(action: "read", access: access, references: store).execute(arguments: .object(["message_ref": .string(ref)])); XCTFail() } catch {}
    }
    func testPartialTextAndUnexpectedReadStatusAreDisclosed() async throws {
        let access = MailFixture(), store = MailReferenceStore()
        let (ref, _) = try await reference(access, store: store)
        let tool = AppleMailTool(action: "read", access: access, references: store)
        await access.replaceRead(mailRow(text: "Excerpt", partial: true))
        let excerpt = try await tool.execute(arguments: .object(["message_ref": .string(ref)]))
        XCTAssertEqual(excerpt.data.object?["partial"], .bool(true)); XCTAssertTrue(excerpt.summary.contains("partial"))
        await access.replaceRead(mailRow(text: "Excerpt", changed: true))
        let changed = try await tool.execute(arguments: .object(["message_ref": .string(ref)]))
        XCTAssertEqual(changed.state, .partiallyCompleted); XCTAssertTrue(changed.summary.contains("read status changed"))
    }
    func testSkippedAmbiguousDuplicateAndWrongAccountSearchResults() async throws {
        let access = MailFixture(), store = MailReferenceStore()
        await access.replaceSearch([mailRow(), mailRow(id: 43)], skipped: 1)
        let search = AppleMailTool(action: "search", access: access, references: store)
        let result = try await search.execute(arguments: .object([:]))
        XCTAssertEqual(result.state, .partiallyCompleted); XCTAssertEqual(result.data.object?["requires_disambiguation"], .bool(true))
        await access.replaceSearch([mailRow(), mailRow()])
        do { _ = try await search.execute(arguments: .object([:])); XCTFail("Duplicate native identity") } catch {}
        await access.replaceSearch([mailRow(account: "different")])
        do { _ = try await search.execute(arguments: .object(["account_id": .string("account-A")])); XCTFail("Wrong requested account") } catch {}
    }
    func testValidationRejectsBadDatesOversizedQueriesAndMalformedNativeRecords() throws {
        for args: JSONValue in [
            .object(["after": .string("2026-11-18T12:00:00")]), .object(["after": .string("tomorrow")]), .object(["after": .string("2026-02-30T12:00:00Z")]), .object(["after": .string("2026-11-18T12:00:00+99:00")]),
            .object(["after": .string("2026-11-18T12:00:00Z"), "before": .string("2026-11-17T12:00:00Z")]),
            .object(["query": .string(String(repeating: "a", count: 201))]), .object(["query": .string("text\0")])
        ] { XCTAssertThrowsError(try MailSearchRequest(args)) }
        XCTAssertNotNil(MailTimestamp.date("2028-02-29T12:00:00+05:30"))
        _ = try MailSearchRequest(.object(["after": .string("2026-11-18T00:00:00-06:00"), "before": .string("2026-11-19T00:00:00-06:00"), "unread_only": .bool(true)]))
        for n in [Double.nan, Double.infinity, -1, 0, 1.5, 2_147_483_648] {
            var row = mailRow().object!; row["native_id"] = .number(n)
            XCTAssertThrowsError(try MailMessageIdentity(.object(row)))
        }
        XCTAssertThrowsError(try MailMessageText(mailRow(text: String(repeating: "🦜", count: 5000))))
    }
    func testReferencesReuseIdentitiesButStayBounded() async throws {
        let store = MailReferenceStore()
        let firstIdentity = try MailMessageIdentity(mailRow())
        let first = await store.reference(firstIdentity), again = await store.reference(firstIdentity)
        XCTAssertEqual(first, again)
        for i in 100...300 { _ = await store.reference(try MailMessageIdentity(mailRow(id: i))) }
        do { _ = try await store.resolve(first); XCTFail("Old reference must be evicted") } catch {}
    }
    func testMailDateAndUnicodeExcerptHelpersExecuteNativelyWithoutMailAccess() async throws {
        let date = AppleMailScript.helpers + "\non run\nreturn my isoDate(my scriptDate(\"2026-11-18T10:00:00-06:00\"))\nend run"
        let result = try await AppleScriptExecutor().executeReviewed(date, input: Data(), targetName: "Mail helper test", timeout: 10)
        XCTAssertEqual(result, "2026-11-18T16:00:00Z")
        let source = AppleMailScript.helpers + #"""

on run
    set d to current application's NSFileHandle's fileHandleWithStandardInput()'s readDataToEndOfFile()
    set s to (current application's NSString's alloc()'s initWithData:d encoding:(current application's NSUTF8StringEncoding)) as text
    return my excerpt(s)
end run
"""#
        let text = String(repeating: "a", count: 15999) + "🦜z"
        let excerpt = try await AppleScriptExecutor().executeReviewed(source, input: Data(text.utf8), targetName: "Mail helper test")
        XCTAssertEqual(excerpt, String(repeating: "a", count: 15999))
        XCTAssertFalse(excerpt.contains("�"))
    }
    func testFixedMailScriptCompilesWithoutExecutingMailOrMutations() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-mail-script-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Mail.applescript")
        try AppleMailScript.source.write(to: file, atomically: true, encoding: .utf8)
        let process = Process(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", dir.appendingPathComponent("Mail.scpt").path, file.path]; process.standardError = errors
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        for forbidden in ["set read status", "send outgoing", "delete message", "account directory", "password of", "source of m"] { XCTAssertFalse(AppleMailScript.source.contains(forbidden)) }
    }
    func testOnlyThreeReadOnlyMailToolsAreRegistered() throws {
        let tools = NativeTools.registry().descriptors.filter { $0.id.hasPrefix("mail.") }
        XCTAssertEqual(Set(tools.map(\.id)), ["mail.accounts", "mail.search", "mail.read"])
        XCTAssertTrue(tools.allSatisfy { $0.risk == .read && $0.capabilities.contains(.mail) && !$0.permissions.isEmpty })
        XCTAssertThrowsError(try NativeTools.registry().tool("mail.send"))
    }
}
