import XCTest
@testable import SottoTools
@testable import SottoSecurity
@testable import SottoProviders
@testable import SottoAgent
@testable import SottoPersistence

private actor Counter { var value = 0; func increment() { value += 1 } }
private struct TestTool: Tool {
    let counter: Counter
    let risk: Risk
    let fails: Bool
    var descriptor: ToolDescriptor { .init(id: "test_action", description: "Test action", properties: ["value": textProperty("Value")], required: ["value"], risk: risk, capabilities: []) }
    func execute(arguments: JSONValue) async throws -> ToolResult { if fails { throw ToolError.unavailable("Actual failure") }; await counter.increment(); return ToolResult("Verified success") }
}
private struct ScriptedProvider: ReasoningProvider {
    var invalid = false
    var throwsNetwork = false
    func models() async throws -> [ModelInfo] { [] }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { c in
            if throwsNetwork { c.finish(throwing: URLError(.notConnectedToInternet)); return }
            if input.count == 1 {
                c.yield(.output([.object(["type": .string("function_call"), "call_id": .string("call_1"), "name": .string("test_action"), "arguments": .string(invalid ? "{\"value\":42}" : "{\"value\":\"hello\"}")])]))
            } else { c.yield(.text("Finished")); c.yield(.output([.object(["type": .string("message"), "role": .string("assistant"), "content": .array([.object(["type": .string("output_text"), "text": .string("Finished")])])])])) }
            c.finish()
        }
    }
}
private actor Events { var states: [AgentState] = []; var results: [ToolResult] = []; var failures: [String] = []
    func receive(_ event: AgentEvent) { switch event { case .state(let state, _): states.append(state); case .result(_, let r): results.append(r); case .failure(_, let s): failures.append(s); default: break } }
}
final class SottoTests: XCTestCase, @unchecked Sendable {
    let args: JSONValue = .object(["value": .string("hello")])
    func testStateTransitionsAndCancellation() {
        var machine = AgentStateMachine()
        XCTAssertFalse(machine.transition(to: .executing))
        for next in [AgentState.listening, .transcribing, .thinking, .awaitingApproval, .executing, .thinking, .completed, .idle] { XCTAssertTrue(machine.transition(to: next)); XCTAssertEqual(machine.state, next) }
        XCTAssertTrue(machine.transition(to: .listening)); XCTAssertTrue(machine.transition(to: .idle))
        XCTAssertFalse(machine.transition(to: .completed))
    }
    func testJSONRoundTrip() throws {
        let value: JSONValue = .object(["text": .string("quote\"\n"), "number": .number(2), "bool": .bool(true), "null": .null, "array": .array([.string("a")])])
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
    func testToolSchemaRejectsUnknownAndWrongTypes() throws {
        let tool = TestTool(counter: Counter(), risk: .read, fails: false)
        XCTAssertThrowsError(try tool.descriptor.validate(.object([:])))
        XCTAssertThrowsError(try tool.descriptor.validate(.object(["value": .number(2)])))
        XCTAssertThrowsError(try tool.descriptor.validate(.object(["value": .string("x"), "approved": .bool(true)])))
        XCTAssertNoThrow(try tool.descriptor.validate(args))
    }
    func testMalformedToolCall() { XCTAssertThrowsError(try ToolCall(item: .object(["type": .string("function_call")]))) }
    func testUnknownToolRejected() { XCTAssertThrowsError(try ToolRegistry([]).tool("shell")) }
    func testHTTPFailuresAndModelCapabilities() throws {
        let url = URL(string: "https://api.openai.com")!
        for code in [401, 403, 429, 500] { XCTAssertThrowsError(try OpenAIProvider.check(HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)) }
        XCTAssertNoThrow(try OpenAIProvider.check(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        XCTAssertFalse(OpenAIProvider.supportsTools("unknown-model")); XCTAssertTrue(OpenAIProvider.supportsTools("gpt-4.1-mini"))
    }
    func testActualResultAndRuntimeStates() async throws {
        let counter = Counter(); let events = Events()
        let runtime = AgentRuntime(registry: ToolRegistry([TestTool(counter: counter, risk: .read, fails: false)]), gate: AuthorizationGate())
        let context = try await runtime.run("Act", provider: ScriptedProvider()) { await events.receive($0) }
        let count = await counter.value; let results = await events.results; let states = await events.states
        XCTAssertEqual(count, 1); XCTAssertEqual(results, [ToolResult("Verified success")]); XCTAssertEqual(states, [.thinking, .executing, .thinking])
        XCTAssertTrue(context.contains { $0.object?["type"]?.string == "function_call_output" })
    }
    func testInvalidModelArgumentsCannotExecute() async throws {
        let counter = Counter(); let events = Events()
        let runtime = AgentRuntime(registry: ToolRegistry([TestTool(counter: counter, risk: .read, fails: false)]), gate: AuthorizationGate())
        _ = try await runtime.run("Act", provider: ScriptedProvider(invalid: true)) { await events.receive($0) }
        let count = await counter.value; let failures = await events.failures
        XCTAssertEqual(count, 0); XCTAssertEqual(failures.count, 1)
    }
    func testFailedToolNeverEmitsSuccess() async throws {
        let events = Events()
        let runtime = AgentRuntime(registry: ToolRegistry([TestTool(counter: Counter(), risk: .read, fails: true)]), gate: AuthorizationGate())
        _ = try await runtime.run("Act", provider: ScriptedProvider()) { await events.receive($0) }
        let results = await events.results; let failures = await events.failures
        XCTAssertTrue(results.isEmpty); XCTAssertEqual(failures, ["Actual failure"])
    }
    func testApprovalBlocksSideEffectsUntilApproved() async throws {
        let gate = AuthorizationGate(); let counter = Counter()
        let tool = TestTool(counter: counter, risk: .consequential, fails: false)
        let presented = expectation(description: "Approval presented")
        let pending = Task { try await gate.authorize(tool.descriptor, arguments: args) { request in
            let count = await counter.value; XCTAssertEqual(count, 0)
            presented.fulfill(); await gate.resolve(request.id, allowed: true)
        }; _ = try await tool.execute(arguments: args) }
        await fulfillment(of: [presented], timeout: 2); try await pending.value
        let count = await counter.value; XCTAssertEqual(count, 1)
    }
    func testDenialHasNoSideEffect() async throws {
        let gate = AuthorizationGate(); let counter = Counter(); let tool = TestTool(counter: counter, risk: .consequential, fails: false)
        do { try await gate.authorize(tool.descriptor, arguments: args) { await gate.resolve($0.id, allowed: false) }; _ = try await tool.execute(arguments: args); XCTFail("Denied tool executed") } catch {}
        let count = await counter.value; XCTAssertEqual(count, 0)
    }
    func testCancellationWhileAwaitingApproval() async throws {
        let gate = AuthorizationGate(); let ready = expectation(description: "Waiting")
        let tool = TestTool(counter: Counter(), risk: .consequential, fails: false)
        let task = Task { try await gate.authorize(tool.descriptor, arguments: args) { _ in ready.fulfill() } }
        await fulfillment(of: [ready], timeout: 2); task.cancel()
        do { try await task.value; XCTFail("Should cancel") } catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
    }
    func testNetworkFailurePropagates() async throws {
        let runtime = AgentRuntime(registry: ToolRegistry([]), gate: AuthorizationGate())
        do { _ = try await runtime.run("Act", provider: ScriptedProvider(throwsNetwork: true)) { _ in }; XCTFail("Expected failure") } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
    func testActivityPersistenceAndDeletion() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try ActivityStore(path: path); let item = Activity(tool: "test", summary: "Confirmed", succeeded: true)
        try await store.append(item)
        let recent = try await store.recent(); XCTAssertEqual(recent.first?.summary, "Confirmed")
        try await store.clear(); let empty = try await store.recent(); XCTAssertTrue(empty.isEmpty)
    }
}
