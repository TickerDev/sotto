import XCTest
import SottoTools
import SottoSecurity
@testable import SottoIntegrations

private actor NotesFixture: AppleNotesAccess {
    var note: AppleNoteSnapshot
    var writes = 0
    var wrongReadback = false
    var failAfterWrite = false
    init(shared: Bool = false, attachments: Int = 0) throws {
        note = try Self.snapshot(text: "Research\nExisting text", html: "<html><body><div>Research</div><div>Existing text</div></body></html>", shared: shared, attachments: attachments)
    }
    static func snapshot(text: String, html: String, shared: Bool = false, attachments: Int = 0) throws -> AppleNoteSnapshot {
        try AppleNoteSnapshot(.object(["id": .string("real-note-id"), "title": .string("Research"), "html": .string(html), "text": .string(text), "folder": .string("Study"), "shared": .bool(shared), "attachments": .number(Double(attachments))]))
    }
    func list(query: String) -> JSONValue { .object(["notes": .array([.object(["id": .string(note.id), "title": .string(note.title)])]), "source": .string("Apple Notes")]) }
    func destination(_ id: String) -> (id: String, name: String) { ("real-folder-id", "Study") }
    func read(_ id: String) throws -> AppleNoteSnapshot {
        if failAfterWrite && writes > 0 { throw ToolError.unavailable("Controlled read-back failure") }; return note
    }
    func create(folder: String, title: String, html: String) throws -> AppleNoteSnapshot { writes += 1; note = try Self.snapshot(text: "Research\nNew text", html: html); return note }
    func update(_ original: AppleNoteSnapshot, html: String) throws -> AppleNoteSnapshot {
        writes += 1
        note = try Self.snapshot(text: wrongReadback ? "Unverified text" : "Research\nExisting text\nNew text", html: html)
        return note
    }
    func change() throws { note = try Self.snapshot(text: "Someone else edited this", html: "<div>Changed</div>") }
    func failReadback() { failAfterWrite = true }
    func corruptReadback() { wrongReadback = true }
}

final class AppleNotesTests: XCTestCase, @unchecked Sendable {
    func testApprovalBindsActualFolderAndFinalTextAndNativeSource() async throws {
        let access = try NotesFixture(), tool = AppleNotesTool(action: "create", access: access)
        let approved = try await tool.authorizationArguments(.object(["title": .string("Research"), "body": .string("New text")]))
        XCTAssertEqual(approved.object?["folder_id"], .string("real-folder-id"))
        let presentation = ApprovalPresentation(Approval(tool: "appleNotes.create", arguments: approved))
        XCTAssertTrue(presentation.fields.contains { $0.value == "Apple Notes · Study" })
        XCTAssertTrue(presentation.fields.contains { $0.value == "New text" })
        let result = try await tool.execute(arguments: approved)
        XCTAssertEqual(result.state, .success)
        XCTAssertEqual(result.data.object?["source"], .string("Apple Notes"))
        XCTAssertNil(result.data.object?["html"])
    }
    func testAppendPreservesMarkupAndReviewsEntireFinalText() async throws {
        let access = try NotesFixture(), tool = AppleNotesTool(action: "update", access: access)
        let note = try await access.read("real-note-id")
        let approved = try await tool.authorizationArguments(.object(["id": .string(note.id), "revision": .string(note.revision), "mode": .string("append"), "body": .string("New text")]))
        XCTAssertEqual(approved.object?["body"], .string("Research\nExisting text\nNew text"))
        let result = try await tool.execute(arguments: approved)
        XCTAssertEqual(result.state, .success)
        let saved = try await access.read(note.id)
        XCTAssertTrue(saved.html.contains("<div>Existing text</div><div>New text</div></body>"))
        do { _ = try await tool.execute(arguments: approved); XCTFail("Must refuse a stale approved append") } catch {}
        let count = await access.writes; XCTAssertEqual(count, 1)
    }
    func testStaleOrUnreviewedTargetsCannotWrite() async throws {
        let access = try NotesFixture(), tool = AppleNotesTool(action: "update", access: access)
        let note = try await access.read("real-note-id")
        let args: JSONValue = .object(["id": .string(note.id), "revision": .string(note.revision), "mode": .string("append"), "body": .string("New text")])
        do { _ = try await tool.execute(arguments: args); XCTFail("No resolved final review") } catch {}
        let reviewed = try await tool.authorizationArguments(args)
        try await access.change()
        do { _ = try await tool.execute(arguments: reviewed); XCTFail("Changed target") } catch {}
        let count = await access.writes; XCTAssertEqual(count, 0)
    }
    func testSharedAndAttachmentBearingNotesAreReadOnly() async throws {
        for access in [try NotesFixture(shared: true), try NotesFixture(attachments: 1)] {
            let note = try await access.read("real-note-id")
            let tool = AppleNotesTool(action: "update", access: access)
            do { _ = try await tool.authorizationArguments(.object(["id": .string(note.id), "revision": .string(note.revision), "body": .string("New text"), "mode": .string("replace")])); XCTFail() } catch {}
            let count = await access.writes; XCTAssertEqual(count, 0)
        }
    }
    func testWrongReadbackIsPartialAndNeverSuccess() async throws {
        let access = try NotesFixture(), tool = AppleNotesTool(action: "update", access: access)
        let note = try await access.read("real-note-id")
        let args = try await tool.authorizationArguments(.object(["id": .string(note.id), "revision": .string(note.revision), "mode": .string("append"), "body": .string("New text")]))
        await access.corruptReadback()
        let result = try await tool.execute(arguments: args)
        XCTAssertEqual(result.state, .partiallyCompleted)
    }
    func testReadbackFailurePreservesActualIdentityAndReportsPartial() async throws {
        let access = try NotesFixture(), tool = AppleNotesTool(action: "create", access: access)
        let args = try await tool.authorizationArguments(.object(["title": .string("Research"), "body": .string("New text")]))
        await access.failReadback()
        let result = try await tool.execute(arguments: args)
        XCTAssertEqual(result.state, .partiallyCompleted)
        XCTAssertEqual(result.data.object?["id"], .string("real-note-id"))
        let count = await access.writes; XCTAssertEqual(count, 1)
    }
    func testHTMLIsEscapedAndMalformedOrOversizedNotesAreRefused() throws {
        let html = AppleNotesText.document(title: "<script>", body: "<img src='https://example.com'>&\"")
        XCTAssertFalse(html.contains("<script>")); XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("&lt;img")); XCTAssertTrue(html.contains("&amp;"))
        XCTAssertThrowsError(try AppleNotesText.appending("new", to: "<html>old</html>"))
        XCTAssertThrowsError(try AppleNotesText.validate(title: "Title", body: String(repeating: "🦜", count: 4000)))
        XCTAssertThrowsError(try AppleNotesText.validate(title: "", body: "text"))
        XCTAssertThrowsError(try AppleNoteSnapshot(.object(["attachments": .number(.nan)])))
        XCTAssertNotEqual(try NotesFixture.snapshot(text: "", html: "a").revision, try NotesFixture.snapshot(text: "", html: "b").revision)
    }
    func testReviewedTransportReallyPassesLiteralUnicodeDataThroughStdin() async throws {
        let source = #"""
        use framework "Foundation"
        set d to current application's NSFileHandle's fileHandleWithStandardInput()'s readDataToEndOfFile()
        return (current application's NSString's alloc()'s initWithData:d encoding:(current application's NSUTF8StringEncoding)) as text
        """#
        let literal = "Private 🦜 résumé \" & <script> $(touch /tmp/never) \n tell application \"Notes\" to delete every note"
        let result = try await AppleScriptExecutor().executeReviewed(source, input: Data(literal.utf8), targetName: "Test", timeout: 10)
        XCTAssertEqual(result, literal)
        do { _ = try await AppleScriptExecutor().executeReviewed(source, input: Data(repeating: 0, count: 128_001), targetName: "Test"); XCTFail() } catch {}
    }
    func testReviewedTransportTimeoutAndCancellationAreReal() async throws {
        do {
            _ = try await AppleScriptExecutor().executeReviewed("delay 5\nreturn \"unexpected\"", input: Data(), targetName: "Test", timeout: 0.05)
            XCTFail("Must time out")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        let task = Task { try await AppleScriptExecutor().executeReviewed("delay 5", input: Data(), targetName: "Test") }
        try await Task.sleep(for: .milliseconds(150)); task.cancel()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testFixedNotesScriptCompilesAgainstInstalledPublicDictionaryWithoutExecution() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-notes-script-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Notes.applescript")
        try AppleNotesScript.source.write(to: source, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        p.arguments = ["-o", dir.appendingPathComponent("Notes.scpt").path, source.path]
        let errors = Pipe(); p.standardError = errors
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Notes.scpt").path))
    }
    func testRegistrationPreservesBothNoteSourcesAndHumanNames() throws {
        let registry = NativeTools.registry()
        for action in ["list", "search", "read", "create", "update"] {
            let tool = try registry.tool("appleNotes." + action)
            XCTAssertTrue(tool.descriptor.name.contains("Apple Note"))
            XCTAssertEqual(tool.descriptor.permissions, ["Automation access to Apple Notes"])
            _ = try registry.tool("notes." + action)
        }
    }
}
