import XCTest
@testable import SottoTools
@testable import SottoIntegrations

private actor StepCount {
    var count = 0
    func increment() { count += 1 }
}
private struct ControlledWorkflowStep: Tool {
    let id: String
    let counter: StepCount
    var delay = false
    var timeout = 1.0
    var fails = false
    var started: @Sendable () -> Void = {}
    var descriptor: ToolDescriptor { ToolDescriptor(id: id, description: "Controlled workflow policy test", properties: id == "files.reveal" ? ["path": textProperty("Path")] : [:], required: id == "files.reveal" ? ["path"] : [], risk: .reversible, capabilities: [], timeoutSeconds: timeout) }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        await counter.increment(); started()
        if delay { try await Task.sleep(for: .seconds(5)) }
        if fails { throw ToolError.unavailable("Controlled failure") }
        return ToolResult("Controlled evidence")
    }
}
final class WorkflowReliabilityTests: XCTestCase, @unchecked Sendable {
    private func step(_ id: String) -> JSONValue { .object(["tool": .string(id), "arguments": .object([:])]) }
    private func args(_ steps: [JSONValue]) -> JSONValue { .object(["name": .string(""), "steps": .array(steps)]) }
    func testFailureKeepsEarlierEvidenceAndRecordsFailedStep() async throws {
        let first = StepCount(); let second = StepCount()
        let registry = ToolRegistry([
            ControlledWorkflowStep(id: "screen.context", counter: first),
            ControlledWorkflowStep(id: "files.reveal", counter: second, fails: true)
        ])
        // files.reveal needs a syntactic path even with a controlled execution adapter.
        let fixturePathStep: JSONValue = .object(["tool": .string("files.reveal"), "arguments": .object(["path": .string("/tmp")])])
        let result = try await WorkflowTool(registry: registry, journal: temporaryWorkflowJournal()).execute(arguments: args([step("screen.context"), fixturePathStep]))
        XCTAssertEqual(result.state, .partiallyCompleted)
        guard case .array(let rows) = result.data.object?["steps"] else { return XCTFail("No step records") }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].object?["result"]?.object?["state"]?.string, "success")
        XCTAssertEqual(rows[1].object?["result"]?.object?["state"]?.string, "failure")
        XCTAssertNotNil(result.data.object?["id"]?.string)
        let counts = await (first.count, second.count)
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testPerStepTimeoutStopsSubsequentActions() async throws {
        let first = StepCount(); let second = StepCount()
        let registry = ToolRegistry([
            ControlledWorkflowStep(id: "screen.context", counter: first, delay: true, timeout: 0.01),
            ControlledWorkflowStep(id: "system.openSettings", counter: second)
        ])
        let result = try await WorkflowTool(registry: registry, journal: temporaryWorkflowJournal()).execute(arguments: args([step("screen.context"), step("system.openSettings")]))
        XCTAssertEqual(result.state, .failure)
        let secondCount = await second.count
        XCTAssertEqual(secondCount, 0)
        XCTAssertTrue(result.summary.contains("timed out"))
    }
    func testCancellationStopsInFlightStepAndNeverStartsTheNext() async throws {
        let first = StepCount(); let second = StepCount()
        let began = expectation(description: "First step started")
        let registry = ToolRegistry([
            ControlledWorkflowStep(id: "screen.context", counter: first, delay: true, timeout: 3, started: { began.fulfill() }),
            ControlledWorkflowStep(id: "system.openSettings", counter: second)
        ])
        let runner = WorkflowTool(registry: registry, journal: temporaryWorkflowJournal())
        let arguments = args([step("screen.context"), step("system.openSettings")])
        let task = Task { try await runner.execute(arguments: arguments) }
        await fulfillment(of: [began], timeout: 1)
        task.cancel()
        let result = try await task.value
        XCTAssertEqual(result.state, .cancelled)
        let secondCount = await second.count
        XCTAssertEqual(secondCount, 0)
    }
}
