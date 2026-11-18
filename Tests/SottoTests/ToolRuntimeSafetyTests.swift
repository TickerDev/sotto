import XCTest
@testable import SottoTools
@testable import SottoAgent
@testable import SottoSecurity
@testable import SottoProviders

private actor RuntimeCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
private struct CountedRuntimeTool: Tool {
    let id: String
    let counter: RuntimeCounter
    var fails = false
    var delay = false
    var risk: Risk = .reversible
    var descriptor: ToolDescriptor { .init(id: id, description: "Controlled safety test", properties: [:], required: [], risk: risk, capabilities: id.hasPrefix("web.") ? [.web] : [.files], timeoutSeconds: delay ? 0.01 : 2) }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        await counter.increment()
        if delay { try await Task.sleep(for: .seconds(2)) }
        if fails { throw ToolError.unavailable("Uncertain side effect") }
        return ToolResult("Test evidence")
    }
}
private struct RejectedPreflightTool: Tool {
    let descriptor = ToolDescriptor(id: "preflight", description: "Controlled rejection", properties: [:], required: [], risk: .read, capabilities: [.calendar])
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue { throw ToolError.invalid("Invalid requested date") }
    func execute(arguments: JSONValue) async throws -> ToolResult { throw ToolError.unavailable("Must not dispatch") }
}
private struct SequenceProvider: ReasoningProvider {
    let names: [String]
    func models() async throws -> [ModelInfo] { [] }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let index = input.filter { $0.object?["type"]?.string == "function_call_output" }.count
            if names.indices.contains(index) {
                continuation.yield(.output([.object(["type": .string("function_call"), "call_id": .string("call-\(index)"), "name": .string(names[index]), "arguments": .string("{}")])]))
            } else { continuation.yield(.output([.object(["role": .string("assistant"), "content": .string("Done")])])) }
            continuation.finish()
        }
    }
}
private actor SafetyEvents {
    var approvals = 0
    var failures = 0
    func receive(_ event: AgentEvent, gate: AuthorizationGate) async {
        switch event {
        case .approval(let approval):
            approvals += 1
            await gate.resolve(approval.id, allowed: false)
        case .failure: failures += 1
        default: break
        }
    }
}
final class ToolRuntimeSafetyTests: XCTestCase, @unchecked Sendable {
    func testRepeatedSuccessfulSideEffectIsNotExecutedAgain() async throws {
        let counter = RuntimeCounter()
        let tool = CountedRuntimeTool(id: "effect", counter: counter)
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate())
        _ = try await runtime.run("Do the effect", provider: SequenceProvider(names: ["effect", "effect"]), emit: { _ in })
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }
    func testUncertainFailedSideEffectIsNotRetriedAutomatically() async throws {
        let counter = RuntimeCounter()
        let tool = CountedRuntimeTool(id: "effect", counter: counter, fails: true)
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate())
        _ = try await runtime.run("Do the effect", provider: SequenceProvider(names: ["effect", "effect"]), emit: { _ in })
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }
    func testUntrustedWebCannotAuthorizePrivateRead() async throws {
        let webCount = RuntimeCounter(); let privateCount = RuntimeCounter(); let gate = AuthorizationGate(); let events = SafetyEvents()
        let tools: [any Tool] = [CountedRuntimeTool(id: "web.fetch", counter: webCount, risk: .read), CountedRuntimeTool(id: "private.read", counter: privateCount, risk: .read)]
        let runtime = AgentRuntime(registry: ToolRegistry(tools), gate: gate)
        _ = try await runtime.run("Read public evidence", provider: SequenceProvider(names: ["web.fetch", "private.read"]), emit: { await events.receive($0, gate: gate) })
        let count = await privateCount.value; let approvals = await events.approvals
        XCTAssertEqual(count, 0); XCTAssertEqual(approvals, 1)
    }
    func testUntrustedBrowserCannotAuthorizePrivateReadOrSearchDisclosure() async throws {
        for destination in ["private.read", "web.search"] {
            let browserCount = RuntimeCounter(); let nextCount = RuntimeCounter()
            let gate = AuthorizationGate(); let events = SafetyEvents()
            let tools: [any Tool] = [CountedRuntimeTool(id: "browser.readPage", counter: browserCount, risk: .read), CountedRuntimeTool(id: destination, counter: nextCount, risk: .read)]
            let runtime = AgentRuntime(registry: ToolRegistry(tools), gate: gate)
            _ = try await runtime.run("Read this page", provider: SequenceProvider(names: ["browser.readPage", destination]), emit: { await events.receive($0, gate: gate) })
            let count = await nextCount.value; let approvals = await events.approvals
            XCTAssertEqual(count, 0); XCTAssertEqual(approvals, 1)
        }
    }
    func testPriorPrivateBrowserOrDocumentContextCannotSilentlyDiscloseThroughSearch() async throws {
        let counter = RuntimeCounter(); let gate = AuthorizationGate(); let events = SafetyEvents()
        let runtime = AgentRuntime(registry: ToolRegistry([CountedRuntimeTool(id: "web.search", counter: counter, risk: .read)]), gate: gate)
        for name in ["browser__readPage", "read_document", "files__read"] {
            let context: [JSONValue] = [.object(["type": .string("function_call"), "name": .string(name)])]
            _ = try await runtime.run("Continue", context: context, provider: SequenceProvider(names: ["web.search"]), emit: { await events.receive($0, gate: gate) })
        }
        let count = await counter.value; let approvals = await events.approvals
        XCTAssertEqual(count, 0); XCTAssertEqual(approvals, 3)
    }
    func testPersonalIntegrationReadsCannotAuthorizeCrossSourceOrNetworkDisclosure() async throws {
        for (origin, target, expected) in [("contacts__search", "contacts.get", 1), ("notes__search", "notes.read", 1), ("notes__read", "contacts.get", 0), ("appleNotes__search", "appleNotes.read", 1), ("appleNotes__read", "web.search", 0), ("appleNotes__read", "notes.read", 0), ("contacts__get", "web.search", 0)] {
            let counter = RuntimeCounter(); let gate = AuthorizationGate(); let events = SafetyEvents()
            let runtime = AgentRuntime(registry: ToolRegistry([CountedRuntimeTool(id: target, counter: counter, risk: .read)]), gate: gate)
            let context: [JSONValue] = [.object(["type": .string("function_call"), "name": .string(origin)])]
            _ = try await runtime.run("Continue the requested lookup", context: context, provider: SequenceProvider(names: [target]), emit: { await events.receive($0, gate: gate) })
            let count = await counter.value; let approvals = await events.approvals
            XCTAssertEqual(count, expected)
            XCTAssertEqual(approvals, expected == 0 ? 1 : 0)
        }
    }
    func testUnrelatedInvalidPreflightDoesNotRequestNativePermission() async throws {
        let preparations = RuntimeCounter()
        let runtime = AgentRuntime(registry: ToolRegistry([RejectedPreflightTool()]), gate: AuthorizationGate())
        _ = try await runtime.run("Invalid date", provider: SequenceProvider(names: ["preflight"]), prepare: { _ in await preparations.increment() }, emit: { _ in })
        let count = await preparations.value
        XCTAssertEqual(count, 0)
    }
    func testCooperativeTimeoutCancelsOperationAndReportsFailure() async throws {
        let counter = RuntimeCounter(); let gate = AuthorizationGate(); let events = SafetyEvents()
        let runtime = AgentRuntime(registry: ToolRegistry([CountedRuntimeTool(id: "slow", counter: counter, delay: true, risk: .read)]), gate: gate)
        let start = ContinuousClock.now
        _ = try await runtime.run("Read", provider: SequenceProvider(names: ["slow"]), emit: { await events.receive($0, gate: gate) })
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        let failures = await events.failures
        XCTAssertEqual(failures, 1)
    }
}
