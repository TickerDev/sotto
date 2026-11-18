import XCTest
@testable import SottoTools
@testable import SottoIntegrations
@testable import SottoSecurity

private actor RecoveryCounter {
    var count = 0
    func increment() { count += 1 }
}
private struct RecoveryAction: Tool {
    let id: String
    let counter: RecoveryCounter
    var descriptor: ToolDescriptor { ToolDescriptor(id: id, description: "Controlled recovery action", properties: [:], required: [], risk: .reversible, capabilities: []) }
    func execute(arguments: JSONValue) async throws -> ToolResult { await counter.increment(); return ToolResult("Controlled result") }
}
final class WorkflowRecoveryTests: XCTestCase, @unchecked Sendable {
    private func fixture() -> (WorkflowJournal, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SottoRecovery-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (WorkflowJournal(directory: directory), directory)
    }
    private func step(_ name: String = "screen.context") -> JSONValue { .object(["tool": .string(name), "arguments": .object([:])]) }
    private func args(_ id: UUID, skip: Bool = false) -> JSONValue { .object(["id": .string(id.uuidString), "skip_uncertain": .bool(skip)]) }
    func testReloadedJournalResumesOnlyPendingActions() async throws {
        let (journal, directory) = fixture(); let first = RecoveryCounter(); let next = RecoveryCounter()
        let registry = ToolRegistry([RecoveryAction(id: "screen.context", counter: first), RecoveryAction(id: "system.openSettings", counter: next)])
        var run = try journal.create(name: "Recovery", steps: [step(), step("system.openSettings")])
        run.steps[0].state = .succeeded; run.steps[0].result = ToolResult("Previously verified")
        run.state = .paused; run = try journal.update(run)
        let restored = WorkflowJournal(directory: directory)
        let tool = ResumeWorkflowTool(registry: registry, journal: restored)
        let reviewed = try await tool.authorizationArguments(args(run.id))
        let result = try await tool.execute(arguments: reviewed)
        XCTAssertEqual(result.state, .success)
        let oldCount = await first.count; let newCount = await next.count
        XCTAssertEqual(oldCount, 0); XCTAssertEqual(newCount, 1)
        XCTAssertEqual(try restored.load(run.id).state, .completed)
        do { _ = try await tool.authorizationArguments(args(run.id)); XCTFail("Completed execution must not be repeated") } catch {}
    }
    func testUnknownOutcomeRequiresExplicitSkipAndNeverReplaysIt() async throws {
        let (journal, directory) = fixture(); let unknown = RecoveryCounter(); let next = RecoveryCounter()
        let registry = ToolRegistry([RecoveryAction(id: "screen.context", counter: unknown), RecoveryAction(id: "system.openSettings", counter: next)])
        var run = try journal.create(name: "Interrupted", steps: [step(), step("system.openSettings")])
        run.steps[0].state = .running; run = try journal.update(run) // Simulates a crash after durable dispatch marker.
        let restored = WorkflowJournal(directory: directory)
        let tool = ResumeWorkflowTool(registry: registry, journal: restored)
        do { _ = try await tool.authorizationArguments(args(run.id)); XCTFail("Unknown action must require review") } catch {}
        let reviewed = try await tool.authorizationArguments(args(run.id, skip: true))
        let presentation = ApprovalPresentation(Approval(tool: "workflows.resume", arguments: reviewed))
        XCTAssertTrue(presentation.fields.contains { $0.label.contains("Uncertain") })
        let result = try await tool.execute(arguments: reviewed)
        XCTAssertEqual(result.state, .partiallyCompleted)
        let count = await unknown.count; let later = await next.count
        XCTAssertEqual(count, 0); XCTAssertEqual(later, 1)
        let finished = try restored.load(run.id)
        XCTAssertEqual(finished.steps[0].state, .skipped)
        XCTAssertEqual(finished.state, .completedWithSkips)
    }
    func testStaleApprovalAndConcurrentLeasePreventExecution() async throws {
        let (journal, _) = fixture(); let counter = RecoveryCounter()
        let registry = ToolRegistry([RecoveryAction(id: "screen.context", counter: counter)])
        var run = try journal.create(name: "Review", steps: [step()])
        let tool = ResumeWorkflowTool(registry: registry, journal: journal)
        let reviewed = try await tool.authorizationArguments(args(run.id))
        run.note = "Changed"; run = try journal.update(run)
        do { _ = try await tool.execute(arguments: reviewed); XCTFail("Stale revision must fail") } catch {}
        let lease = try journal.lease(run.id)
        defer { withExtendedLifetime(lease) {} }
        XCTAssertThrowsError(try journal.lease(run.id))
        let fresh = try await tool.authorizationArguments(args(run.id))
        do { _ = try await tool.execute(arguments: fresh); XCTFail("Concurrent execution must fail") } catch {}
        let count = await counter.count; XCTAssertEqual(count, 0)
    }
    func testSkippingFinalUncertainActionFinishesWithoutDispatchOrSuccessClaim() async throws {
        let (journal, _) = fixture(); let counter = RecoveryCounter()
        let registry = ToolRegistry([RecoveryAction(id: "screen.context", counter: counter)])
        var run = try journal.create(name: "Final action", steps: [step()])
        run.steps[0].state = .running; run = try journal.update(run)
        let tool = ResumeWorkflowTool(registry: registry, journal: journal)
        let reviewed = try await tool.authorizationArguments(args(run.id, skip: true))
        XCTAssertEqual(reviewed.object?["steps"], .array([]))
        XCTAssertEqual(tool.descriptor.inputSchema.object?["properties"]?.object?["steps"]?.object?["minItems"], .number(0))
        let result = try await tool.execute(arguments: reviewed)
        XCTAssertEqual(result.state, .partiallyCompleted)
        XCTAssertEqual(try journal.load(run.id).state, .completedWithSkips)
        let count = await counter.count; XCTAssertEqual(count, 0)
    }
    func testCorruptOrUnwritableJournalCannotDispatchNativeActions() async throws {
        let (journal, directory) = fixture(); let counter = RecoveryCounter()
        let registry = ToolRegistry([RecoveryAction(id: "screen.context", counter: counter)])
        let run = try journal.create(name: "Corrupt", steps: [step()])
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent(run.id.uuidString + ".json"))
        XCTAssertThrowsError(try journal.load(run.id))
        do { _ = try await ResumeWorkflowTool(registry: registry, journal: journal).authorizationArguments(args(run.id)); XCTFail("Corrupt recovery must be refused") } catch {}
        let file = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let bad = WorkflowJournal(directory: file)
        do { _ = try await WorkflowTool(registry: registry, journal: bad).execute(arguments: .object(["name": .string(""), "steps": .array([step()])]))
            XCTFail("No effects without durable recovery")
        } catch {}
        let count = await counter.count; XCTAssertEqual(count, 0)
    }
    func testActualNativeReadOnlyResumeAndOwnerOnlyFile() async throws {
        let (journal, directory) = fixture()
        var run = try journal.create(name: "Native read", steps: [step(), step()])
        let native = try NativeTools.registry().tool("screen.context")
        run.steps[0].state = .succeeded; run.steps[0].result = try await native.execute(arguments: .object([:]))
        run.state = .paused; run = try journal.update(run)
        let restored = WorkflowJournal(directory: directory)
        let tool = ResumeWorkflowTool(registry: NativeTools.registry(), journal: restored)
        let result = try await tool.execute(arguments: try await tool.authorizationArguments(args(run.id)))
        XCTAssertEqual(result.state, .success)
        let final = try restored.load(run.id)
        XCTAssertNotNil(final.steps[1].result?.data.object?["bundle_id"]?.string)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(run.id.uuidString + ".json").path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
