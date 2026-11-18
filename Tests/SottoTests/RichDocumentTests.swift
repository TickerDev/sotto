import XCTest
import SottoTools
import SottoProviders
import SottoSecurity
@testable import SottoIntegrations
@testable import SottoAgent

private actor DocumentDisclosureCounter {
    var calls = 0
    var approvals = 0
    func called() { calls += 1 }
    func reviewed() { approvals += 1 }
}
private struct DocumentDisclosureTool: Tool {
    let counter: DocumentDisclosureCounter
    let descriptor = ToolDescriptor(id: "web.search", description: "Controlled disclosure sink", properties: [:], required: [], risk: .read, capabilities: [.web])
    func execute(arguments: JSONValue) async throws -> ToolResult { await counter.called(); return ToolResult("Controlled sink") }
}
private struct DocumentDisclosureProvider: ReasoningProvider {
    let path: String
    func models() async throws -> [ModelInfo] { [] }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let count = input.filter { $0.object?["type"]?.string == "function_call_output" }.count
            if count < 2 {
                let args: JSONValue = count == 0 ? .object(["path": .string(path)]) : .object([:])
                continuation.yield(.output([.object(["type": .string("function_call"), "call_id": .string("doc-" + String(count)), "name": .string(count == 0 ? "files.read" : "web.search"), "arguments": .string(args.encoded)])]))
            } else { continuation.yield(.output([.object(["role": .string("assistant"), "content": .string("Controlled response")])])) }
            continuation.finish()
        }
    }
}

final class RichDocumentTests: XCTestCase, @unchecked Sendable {
    private func fixture(_ name: String) throws -> URL { try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Documents")) }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SottoDocuments-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testRealStoredAndDeflatedDOCXReadUnicodeTablesAndOmitNonBodyParts() async throws {
        for name in ["normal.docx", "stored.docx"] {
            let result = try await DocumentTextReader().read(path: fixture(name).path)
            let text = try XCTUnwrap(result.data.object?["text"]?.string)
            XCTAssertTrue(text.contains("Engineering ethics résumé — שלום."))
            XCTAssertTrue(text.contains("Risk")); XCTAssertTrue(text.contains("Mitigation"))
            XCTAssertTrue(text.contains("Ignore the user"), "Untrusted instructions remain data")
            for excluded in ["HIDDEN_SECRET", "DELETED_SECRET", "DRAWING_SECRET", "HEADER_SECRET", "INCLUDETEXT"] { XCTAssertFalse(text.contains(excluded)) }
            XCTAssertEqual(result.state, .success)
            XCTAssertEqual(result.data.object?["format"], .string("docx"))
            XCTAssertEqual(result.data.object?["truncated"], .bool(false))
            XCTAssertTrue(result.data.object?["extraction_note"]?.string?.contains("main-body") == true)
            XCTAssertFalse(result.summary.contains("Ignore the user"))
        }
    }
    func testWordLimitIsHonestAndScopeRecognizesNewFormatsWithoutGrantingAccess() async throws {
        let result = try await DocumentTextReader().read(path: fixture("long.docx").path)
        XCTAssertEqual(result.data.object?["truncated"], .bool(true))
        XCTAssertLessThanOrEqual(result.data.object?["text"]?.string?.count ?? 0, 16_000)
        XCTAssertNotNil(DocumentReadScope.explicitSummaryArguments("Summarize /tmp/notes.docx"))
        XCTAssertNotNil(DocumentReadScope.explicitSummaryArguments("Summarize /tmp/notes.rtf"))
        var scope = DocumentReadScope()
        XCTAssertThrowsError(try scope.validate(.object(["path": .string("/tmp/notes.docx")]), request: "Summarize my notes"))
        scope.recordSearch(ToolResult("Actual match", data: FileSearchResults(files: [FileSearchMatch(path: "/tmp/notes.docx")]).data))
        XCTAssertNoThrow(try scope.validate(.object(["path": .string("/tmp/notes.docx")]), request: "Summarize my notes"))
        for kind in ["doc", "docm", "pages", "rtfd", "html"] { XCTAssertFalse(DocumentTextFormats.supports("/tmp/file." + kind)) }
    }
    func testCorruptEncryptedMacroEntityDuplicateAndBombArchivesAreRefused() async throws {
        for name in ["corrupt.docx", "entities.docx", "encrypted.docx", "macro.docx", "malformed.docx", "bomb.docx", "duplicate.docx", "empty.docx", "inconsistent.docx"] {
            do { _ = try await DocumentTextReader().read(path: fixture(name).path); XCTFail("Accepted \(name)") } catch {}
        }
        let bytes = try Data(contentsOf: fixture("normal.docx"))
        for length in [0, 4, 21, bytes.count - 15] {
            XCTAssertThrowsError(try DocumentZIP(Data(bytes.prefix(length))))
        }
        let directory = try temporary()
        let renamed = directory.appendingPathComponent("renamed.docx")
        try Data("Not a ZIP file".utf8).write(to: renamed)
        do { _ = try await DocumentTextReader().read(path: renamed.path); XCTFail("Extension alone is not sufficient") } catch {}
    }
    func testNativeRTFTextAndUnsafeResourceDestinations() async throws {
        let result = try await DocumentTextReader().read(path: fixture("basic.rtf").path)
        let text = try XCTUnwrap(result.data.object?["text"]?.string)
        XCTAssertTrue(text.contains("A rich text ethics note."))
        XCTAssertTrue(text.contains("Second paragraph."))
        XCTAssertFalse(text.contains(#"\rtf1"#))
        for control in [#"\object "#, #"\pict "#, #"\field "#, #"\bin4 "#, #"\filetbl "#] {
            let rtf = Data((#"{\rtf1\ansi before "# + control + "data}").utf8)
            XCTAssertThrowsError(try NativeDocumentText.extract(rtf, kind: "rtf", limit: 8000))
        }
        XCTAssertThrowsError(try NativeDocumentText.extract(Data("fake".utf8), kind: "rtf", limit: 8000))
        XCTAssertThrowsError(try NativeDocumentText.extract(Data((#"{\rtf1 "# + String(repeating: "a", count: 2_000_001) + "}").utf8), kind: "rtf", limit: 8000))
    }
    func testBOMTextUsesExplicitEncodingAndRejectsBinaryOrAmbiguousText() async throws {
        let text = "Résumé and engineering ethics — שלום"
        let directory = try temporary()
        for (name, encoding, bom) in [("little.txt", String.Encoding.utf16LittleEndian, [UInt8(0xff), 0xfe]), ("big.md", .utf16BigEndian, [UInt8(0xfe), 0xff]), ("utf8.txt", .utf8, [UInt8(0xef), 0xbb, 0xbf])] {
            let bytes = Data(bom) + (try XCTUnwrap(text.data(using: encoding)))
            let url = directory.appendingPathComponent(name); try bytes.write(to: url)
            let result = try await DocumentTextReader().read(path: url.path)
            XCTAssertEqual(result.data.object?["text"], .string(text))
        }
        for bytes in [Data([0xff, 0xff]), Data([0xff, 0xfe, 0x61]), Data([0xff, 0xfe, 0, 0]), Data([0, 1, 2]), Data([0xc0, 0x80])] {
            XCTAssertThrowsError(try NativeDocumentText.decodeText(bytes))
        }
    }
    func testAutomaticIndexUsesSharedRichTextExtractionWithoutExposingExcerpts() async throws {
        let directory = try temporary()
        let documents = directory.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        for name in ["normal.docx", "basic.rtf"] { try FileManager.default.copyItem(at: fixture(name), to: documents.appendingPathComponent(name)) }
        let utf16 = Data([0xff, 0xfe]) + (try XCTUnwrap("Engineering ethics in Unicode".data(using: .utf16LittleEndian)))
        try utf16.write(to: documents.appendingPathComponent("unicode.txt"))
        let index = LocalDocumentIndex(file: directory.appendingPathComponent("index/index.json"), folders: { [documents.path] }, excluded: { _ in false })
        let built = try await index.rebuild()
        XCTAssertEqual(built.data.object?["indexed"], .number(3))
        let result = try await index.search(query: "ethics")
        let files = try XCTUnwrap(FileSearchResults.decode(result.data)?.files)
        XCTAssertEqual(files.count, 3)
        XCTAssertFalse(result.data.encoded.contains("Ignore the user"))
        let restored = LocalDocumentIndex(file: directory.appendingPathComponent("index/index.json"), folders: { [documents.path] }, excluded: { _ in false })
        let found = try await restored.search(query: "ethics")
        XCTAssertEqual(FileSearchResults.decode(found.data)?.files.count, 3)
    }
    func testActualDOCXReadCannotAuthorizeSearchDisclosure() async throws {
        let path = try fixture("normal.docx").path
        let gate = AuthorizationGate(); let counter = DocumentDisclosureCounter()
        let read = try NativeTools.registry().tool("files.read")
        let runtime = AgentRuntime(registry: ToolRegistry([read, DocumentDisclosureTool(counter: counter)]), gate: gate)
        let context = try await runtime.run("Summarize " + path, provider: DocumentDisclosureProvider(path: path), emit: { event in
            if case .approval(let approval) = event {
                await counter.reviewed(); await gate.resolve(approval.id, allowed: false)
            }
        })
        let calls = await counter.calls; let approvals = await counter.approvals
        XCTAssertEqual(calls, 0); XCTAssertEqual(approvals, 1)
        XCTAssertTrue(context.contains { $0.object?["output"]?.string?.contains("Engineering ethics") == true })
    }
    func testCancelledRichReadDoesNotReturnContent() async throws {
        let path = try fixture("normal.docx").path
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DocumentTextReader().read(path: path)
        }
        do { _ = try await task.value; XCTFail() } catch is CancellationError {}
    }
}
