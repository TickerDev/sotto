import XCTest
import SottoTools
import SottoSecurity
@testable import SottoIntegrations

private actor DraftFixture: MailDraftAccess {
    var count = 0
    var fail = false
    var mismatch = false
    var request: MailDraftRequest?
    func accounts() -> JSONValue { .object(["accounts": .array([.object(["id": .string("actual-account"), "name": .string("Study"), "enabled": .bool(true), "addresses": .array([.string("me@example.test")])])])]) }
    func create(_ request: MailDraftRequest) throws -> JSONValue {
        count += 1; self.request = request
        if fail { throw ToolError.unavailable("Uncertain dispatch") }
        return .object(["native_id": .number(42)])
    }
    func read(_ id: Int) -> JSONValue {
        guard let request else { return .null }
        return .object(["native_id": .number(Double(id)), "sender": .string(request.sender), "subject": .string(request.subject),
                        "body": .string(mismatch ? "Unexpected signature" : request.body), "to": .array(request.to.map(JSONValue.string)),
                        "cc_count": .number(0), "bcc_count": .number(0), "visible": .bool(true)])
    }
    func setFailure() { fail = true }
    func setMismatch() { mismatch = true }
}
final class MailDraftTests: XCTestCase, @unchecked Sendable {
    private var proposal: JSONValue { .object(["account_id": .string("actual-account"), "sender": .string("me@example.test"),
        "to": .array([.string("professor@example.test")]), "subject": .string("Thank you"), "body": .string("Thank you for your help.\nRegards")]) }
    private func storage() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SottoDraftTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("mail/attempts.json")
    }
    func testExactReviewAndIndependentReadback() async throws {
        let file = try storage(), access = DraftFixture(), tool = MailDraftTool(access: access, journal: MailDraftJournal(file: file))
        let args = try await tool.authorizationArguments(proposal)
        XCTAssertEqual(args.object?["account_name"], .string("Study"))
        let presentation = ApprovalPresentation(Approval(tool: "mail.draft", arguments: args))
        for text in ["me@example.test", "professor@example.test", "Thank you", "Thank you for your help.\nRegards"] { XCTAssertTrue(presentation.fields.contains { $0.value == text }) }
        let result = try await tool.execute(arguments: args)
        XCTAssertEqual(result.state, .success); XCTAssertEqual(result.data.object?["native_id"], .number(42))
        XCTAssertEqual(result.data.object?["send_requested"], .bool(false))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("professor"))
    }
    func testUncertainCreationIsNotRepeatedAfterRelaunch() async throws {
        let file = try storage(), access = DraftFixture()
        await access.setFailure()
        let first = MailDraftTool(access: access, journal: MailDraftJournal(file: file))
        let args = try await first.authorizationArguments(proposal)
        let result = try await first.execute(arguments: args); XCTAssertEqual(result.state, .partiallyCompleted)
        let relaunched = MailDraftTool(access: access, journal: MailDraftJournal(file: file))
        let retry = try await relaunched.execute(arguments: args); XCTAssertEqual(retry.state, .partiallyCompleted)
        let count = await access.count; XCTAssertEqual(count, 1)
    }
    func testMismatchIsPartialAndPreservesNativeID() async throws {
        let access = DraftFixture(); await access.setMismatch()
        let tool = MailDraftTool(access: access, journal: MailDraftJournal(file: try storage()))
        let args = try await tool.authorizationArguments(proposal)
        let result = try await tool.execute(arguments: args)
        XCTAssertEqual(result.state, .partiallyCompleted); XCTAssertEqual(result.data.object?["native_id"], .number(42))
    }
    func testUnreviewedOrWrongSenderCannotDispatch() async throws {
        let access = DraftFixture()
        let tool = MailDraftTool(access: access, journal: MailDraftJournal(file: try storage()))
        do { _ = try await tool.execute(arguments: proposal); XCTFail() } catch {}
        var wrong = proposal.object!; wrong["sender"] = .string("other@example.test")
        do { _ = try await tool.authorizationArguments(.object(wrong)); XCTFail() } catch {}
        let count = await access.count; XCTAssertEqual(count, 0)
    }
    func testHeaderInjectionRecipientBoundsAndBodyLimits() throws {
        for (key, value): (String, JSONValue) in [
            ("subject", .string("Hi\r\nBcc: stranger@example.test")), ("sender", .string("Name <me@example.test>")),
            ("to", .array([.string("a@example.test,b@example.test")])), ("to", .array([.string("a@example.test"), .string("A@example.test")])),
            ("body", .string(String(repeating: "🦜", count: 4000)))
        ] {
            var fields = proposal.object!; fields[key] = value
            XCTAssertThrowsError(try MailDraftRequest(.object(fields)))
        }
    }
    func testCorruptReceiptsArePreservedAndCancellationDoesNotReserve() async throws {
        let file = try storage()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("bad receipts".utf8); try corrupt.write(to: file)
        let journal = MailDraftJournal(file: file)
        do { _ = try await journal.reserve(MailDraftRequest(proposal).fingerprint); XCTFail() } catch {}
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        let clean = MailDraftJournal(file: try storage())
        let hash = try MailDraftRequest(proposal).fingerprint
        let task = Task { try await Task.sleep(for: .seconds(1)); return try await clean.reserve(hash) }; task.cancel()
        do { _ = try await task.value; XCTFail() } catch {}
        let reserved = try await clean.reserve(hash); XCTAssertTrue(reserved)
    }
    func testConcurrentJournalInstancesCannotReserveTwice() async throws {
        let file = try storage(), hash = try MailDraftRequest(proposal).fingerprint
        let a = MailDraftJournal(file: file), b = MailDraftJournal(file: file)
        async let first: Bool? = try? a.reserve(hash)
        async let second: Bool? = try? b.reserve(hash)
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 == true }.count, 1)
        let repeatAttempt = try await MailDraftJournal(file: file).reserve(hash)
        XCTAssertFalse(repeatAttempt)
    }
    func testDraftScriptCompilesAgainstPublicMailDictionaryAndHasNoSendCommand() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Draft.applescript"); try MailDraftScript.source.write(to: file, atomically: true, encoding: .utf8)
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile"); p.arguments = ["-o", dir.appendingPathComponent("Draft.scpt").path, file.path]; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        XCTAssertFalse(MailDraftScript.source.contains("send ")); XCTAssertFalse(MailDraftScript.source.contains("save m"))
    }
}
