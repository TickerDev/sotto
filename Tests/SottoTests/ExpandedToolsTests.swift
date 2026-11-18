import XCTest
@testable import SottoTools
@testable import SottoProviders
@testable import SottoIntegrations
@testable import SottoAgent

final class ExpandedToolsTests: XCTestCase, @unchecked Sendable {
    func testSafeMoveAndCollisionDoesNotOverwrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.txt")
        let target = root.appendingPathComponent("target.txt")
        try Data("original".utf8).write(to: original)
        try Data("keep".utf8).write(to: target)
        let tool = FileManagementTool(action: "move")
        let args: JSONValue = .object(["path": .string(original.path), "destination": .string(target.path)])
        do { _ = try await tool.execute(arguments: args); XCTFail("Collision must fail") } catch {}
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
        try FileManager.default.removeItem(at: target)
        let result = try await tool.execute(arguments: args)
        XCTAssertEqual(result.state, .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
        do {
            _ = try await FileManagementTool(action: "rename").execute(arguments: .object(["path": .string(target.path), "name": .string("../escape")]))
            XCTFail("Traversal must fail")
        } catch {}
    }
    func testPublicWebPolicyAndRedirectDestinationRules() throws {
        for value in ["file:///etc/passwd", "javascript:alert(1)", "http://swift.org", "https://127.0.0.1", "https://[::1]", "https://user:password@swift.org", "https://swift.org:444", "https://device.local", "https://swift.org.evil.example"] {
            XCTAssertThrowsError(try PublicWebPolicy.url(value, retrieval: true), value)
        }
        XCTAssertNoThrow(try PublicWebPolicy.url("https://www.swift.org/documentation/", retrieval: true))
        XCTAssertThrowsError(try PublicWebPolicy.url("https://unconfigured.example/", retrieval: true))
        XCTAssertThrowsError(try PublicWebPolicy.url("https://swift.org./", retrieval: true))
    }
    func testHTMLExtractionKeepsSafeAbsoluteLinks() {
        let html = #"<title>Example</title><script>do bad things</script><a href="/guide">Guide</a><a href="javascript:bad()">bad</a><a href="https://example.org/file.pdf">PDF</a>"#
        XCTAssertFalse(WebText.plain(html).contains("do bad things"))
        let links = WebText.links(html, base: URL(string: "https://swift.org")!)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links.first?.object?["url"]?.string, "https://swift.org/guide")
        XCTAssertEqual(links.last?.object?["kind"]?.string, "pdf")
    }
    func testResultBackwardCompatibilityAndPartialState() throws {
        let old = Data(#"{"summary":"Existing result","data":null}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ToolResult.self, from: old).state, .success)
        let result = ToolResult("Not fully verified", state: .partiallyCompleted)
        XCTAssertEqual(try JSONDecoder().decode(ToolResult.self, from: JSONEncoder().encode(result)), result)
    }
    func testNamespacedProviderMappingAndSchemas() throws {
        let tool = TimerTool(action: "start")
        XCTAssertEqual(tool.descriptor.providerName, "timers__start")
        let call = try ToolCall(item: .object(["type": .string("function_call"), "call_id": .string("one"), "name": .string("timers__start"), "arguments": .string("{}")]))
        XCTAssertEqual(call?.name, "timers.start")
        XCTAssertThrowsError(try tool.descriptor.validate(.object(["seconds": .string("10"), "name": .string("")])))
        XCTAssertThrowsError(try WebSearchTool().descriptor.validate(.object(["query": .string("swift"), "offset": .number(0.5)])))
        XCTAssertNoThrow(try tool.descriptor.validate(.object(["seconds": .number(600), "name": .string("")])))
    }
    func testNativeRoutingWithoutModel() throws {
        XCTAssertEqual(NativeCommandProvider(command: "Set a ten-minute timer.")?.tool, "timers.start")
        XCTAssertEqual(NativeCommandProvider(command: "Show my active timers.")?.tool, "timers.list")
        XCTAssertEqual(NativeCommandProvider(command: "Open Safari.")?.tool, "applications")
        XCTAssertEqual(NativeCommandProvider(command: "What application am I using?")?.tool, "screen.context")
        XCTAssertNil(NativeCommandProvider(command: "set a ten minute timer and delete my files"))
    }
    func testTimerPersistenceReadsAbsoluteDeadline() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let timer = SottoTimer(id: "fixture", name: "Fixture", deadline: Date().addingTimeInterval(600))
        try JSONEncoder().encode([timer]).write(to: file)
        let engine = TimerEngine(file: file)
        let list = try await engine.list()
        XCTAssertEqual(list.first?.id, "fixture")
        _ = try await engine.cancel(id: "fixture")
        let restored = TimerEngine(file: file)
        let empty = try await restored.list()
        XCTAssertTrue(empty.isEmpty)
    }
    func testLiveReadOnlySystemAndFileMetadata() async throws {
        let result = try await SystemInfoTool().execute(arguments: .object([:]))
        XCTAssertEqual(result.state, .success)
        XCTAssertNotNil(result.data.object?["os"]?.string)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("Sotto native verification".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let info = try await FileManagementTool(action: "info").execute(arguments: .object(["path": .string(file.path)]))
        XCTAssertEqual(info.data.object?["bytes"], .number(25))
    }
}

final class LiveExpandedWebTests: XCTestCase, @unchecked Sendable {
    private func enabled() throws {
        guard ProcessInfo.processInfo.environment["SOTTO_LIVE_WEB"] == "1" else { throw XCTSkip("Set SOTTO_LIVE_WEB=1 to exercise actual public APIs") }
    }
    func testActualSearchImagesPublicationsAndPageRetrieval() async throws {
        try enabled()
        let search = try await WikipediaSearchProvider().search(query: "Swift programming language", offset: 0)
        XCTAssertFalse(search.results.isEmpty)
        let images = try await ImageSearchTool().execute(arguments: .object(["query": .string("Yosemite landscape")]))
        guard case .array(let rows) = images.data.object?["images"] else { return XCTFail("Missing images") }
        XCTAssertFalse(rows.isEmpty)
        let documents = try await DocumentSearchTool().execute(arguments: .object(["query": .string("phishing"), "from_date": .string("")]))
        guard case .array(let publications) = documents.data.object?["documents"] else { return XCTFail("Missing publications") }
        XCTAssertFalse(publications.isEmpty)
        let page = try await WebPageTool(action: "fetch").execute(arguments: .object(["url": .string("https://www.swift.org/documentation/")]))
        XCTAssertFalse(page.data.object?["text"]?.string?.isEmpty ?? true)
    }
    func testActualPDFDownloadAndExtraction() async throws {
        try enabled()
        let url = "https://raw.githubusercontent.com/mozilla/pdf.js/master/test/pdfs/tracemonkey.pdf"
        let result = try await WebDocumentTool(action: "download").execute(arguments: .object(["url": .string(url)]))
        guard let path = result.data.object?["path"]?.string else { return XCTFail("No saved file") }
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent()) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let read = try await WebDocumentTool(action: "readPDF").execute(arguments: .object(["url": .string(url)]))
        guard case .array(let pages) = read.data.object?["pages"] else { return XCTFail("No PDF pages") }
        XCTAssertFalse(pages.isEmpty)
        XCTAssertTrue(pages.contains { $0.object?["text"]?.string?.contains("Trace") == true })
    }
}

private actor WorkflowCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
private struct WorkflowFixtureTool: Tool {
    let counter: WorkflowCounter
    let state: ToolResultState
    let descriptor = ToolDescriptor(id: "apps.open", description: "Fixture", properties: ["bundle_id": textProperty("App")], required: ["bundle_id"], risk: .reversible, capabilities: [.applications])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        await counter.increment()
        return ToolResult("Fixture evidence", state: state)
    }
}
final class WorkflowExecutionTests: XCTestCase, @unchecked Sendable {
    private func step(_ tool: String) -> JSONValue { .object(["tool": .string(tool), "arguments": .object(["bundle_id": .string("com.example.fixture")])]) }
    func testWorkflowPrevalidatesEveryStepBeforeAnySideEffect() async throws {
        let counter = WorkflowCounter()
        let workflow = WorkflowTool(registry: ToolRegistry([WorkflowFixtureTool(counter: counter, state: .success)]), journal: temporaryWorkflowJournal())
        do {
            _ = try await workflow.execute(arguments: .object(["name": .string(""), "steps": .array([step("apps.open"), step("shell")])]))
            XCTFail("Must reject unsupported second step before executing the first")
        } catch {}
        let count = await counter.count
        XCTAssertEqual(count, 0)
    }
    func testWorkflowStopsOnPartialResult() async throws {
        let counter = WorkflowCounter()
        let workflow = WorkflowTool(registry: ToolRegistry([WorkflowFixtureTool(counter: counter, state: .partiallyCompleted)]), journal: temporaryWorkflowJournal())
        let result = try await workflow.execute(arguments: .object(["name": .string(""), "steps": .array([step("apps.open"), step("apps.open")])]))
        XCTAssertEqual(result.state, .partiallyCompleted)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
    func testShortcutsTransportRejectsOptionInjection() async throws {
        for args in [["run", "--help"], ["run", "name", "--input-path", "/etc/passwd"], ["delete", "all"]] {
            do { _ = try await AppleScriptExecutor().shortcuts(args); XCTFail("Must reject unsafe arguments") } catch {}
        }
    }
}

final class LiveExpandedNativeTests: XCTestCase, @unchecked Sendable {
    func testActualApplicationDiscoveryAudioAndForegroundContext() async throws {
        let apps = try await AppLifecycleTool(action: "list").execute(arguments: .object([:]))
        guard case .array(let rows) = apps.data else { return XCTFail("No application list") }
        XCTAssertTrue(rows.contains { $0.object?["bundle_id"]?.string == "com.apple.Safari" })
        let audio = try await AudioOutputTool().execute(arguments: .object(["action": .string("list"), "device_id": .number(0)]))
        XCTAssertEqual(audio.state, .success)
        let context = try await ContextTool(action: "screen.context").execute(arguments: .object([:]))
        XCTAssertNotNil(context.data.object?["bundle_id"]?.string)
    }
    func testActualSafariLaunch() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_LIVE_NATIVE"] == "1" else { throw XCTSkip("Set SOTTO_LIVE_NATIVE=1 to launch Safari") }
        let result = try await ApplicationTool().execute(arguments: .object(["action": .string("open"), "bundle_id": .string("com.apple.Safari")]))
        XCTAssertEqual(result.state, .success)
    }
}
