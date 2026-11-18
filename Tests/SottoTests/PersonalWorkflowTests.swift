import XCTest
@testable import SottoIntegrations
@testable import SottoTools
@testable import SottoUI
@testable import SottoSecurity

final class PersonalWorkflowTests: XCTestCase, @unchecked Sendable {
    private func fixture() -> (WorkflowStore, UserDefaults) {
        let suite = "SottoWorkflowTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (WorkflowStore(defaults: defaults), defaults)
    }
    private var context: JSONValue { .object(["tool": .string("screen.context"), "arguments": .object([:])]) }
    private func args(name: String = "Study session", id: String = "", revision: Double = 0, steps: [JSONValue]? = nil) -> JSONValue {
        .object(["name": .string(name), "id": .string(id), "revision": .number(revision), "steps": .array(steps ?? [context])])
    }
    func testSaveListUpdateRemoveRealIsolatedPreferencesWithoutRunningActions() async throws {
        let (store, defaults) = fixture()
        let registry = NativeTools.registry()
        let save = SaveWorkflowTool(registry: registry, store: store)
        let result = try await save.execute(arguments: args())
        XCTAssertEqual(result.state, .success)
        XCTAssertTrue(result.summary.contains("have not been run"))
        let first = try XCTUnwrap(store.all().first)
        let restored = WorkflowStore(defaults: defaults)
        XCTAssertEqual(try restored.all(), [first])
        let list = try await ListWorkflowsTool(store: restored).execute(arguments: .object([:]))
        guard case .array(let values) = list.data.object?["workflows"] else { return XCTFail("No saved workflow") }
        XCTAssertEqual(values.first?.object?["revision"], .number(1))
        _ = try await save.execute(arguments: args(name: "Study setup", id: first.id.uuidString, revision: 1))
        let updated = try XCTUnwrap(store.all().first)
        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.revision, 2)
        do {
            _ = try await save.execute(arguments: args(id: first.id.uuidString, revision: 1))
            XCTFail("Stale update must fail")
        } catch {}
        do { try store.remove(id: first.id, name: first.name, expectedRevision: 1); XCTFail("Stale deletion must fail") } catch {}
        _ = try await RemoveWorkflowTool(store: store).execute(arguments: .object(["id": .string(updated.id.uuidString), "name": .string(updated.name), "revision": .number(2)]))
        XCTAssertTrue(try store.all().isEmpty)
    }
    func testSavedWorkflowRunsActualReadOnlyNativeAction() async throws {
        let (store, _) = fixture()
        let registry = NativeTools.registry()
        _ = try store.upsert(SavedWorkflow(name: "Context check", steps: .array([context])), expectedRevision: nil, registry: registry)
        let runner = WorkflowTool(registry: registry, store: store, journal: temporaryWorkflowJournal())
        let frozen = try await runner.authorizationArguments(.object(["name": .string("Context check"), "steps": .array([])]))
        let result = try await runner.execute(arguments: frozen)
        XCTAssertEqual(result.state, .success)
        guard case .array(let rows) = result.data.object?["steps"] else { return XCTFail("Missing step records") }
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(result.data.object?["id"]?.string)
        XCTAssertNotNil(rows[0].object?["result"]?.object?["data"]?.object?["bundle_id"]?.string)
    }
    func testDuplicatesInvalidRangesAndArbitraryToolsCannotBeSaved() async throws {
        let (store, _) = fixture()
        let save = SaveWorkflowTool(registry: NativeTools.registry(), store: store)
        _ = try await save.execute(arguments: args())
        let invalid: [JSONValue] = [
            args(name: "  STUDY SESSION "),
            args(name: "Bad timer", steps: [.object(["tool": .string("timers.start"), "arguments": .object(["seconds": .number(-1), "name": .string("")])])]),
            args(name: "Bad volume", steps: [.object(["tool": .string("audio.volume"), "arguments": .object(["action": .string("set"), "value": .string("101")])])]),
            args(name: "Shell", steps: [.object(["tool": .string("shell"), "arguments": .object([:])])]),
            args(name: "Nested", steps: [.object(["tool": .string("workflows.run"), "arguments": .object([:])])]),
            args(name: "Unknown field", steps: [.object(["tool": .string("screen.context"), "arguments": .object(["approved": .bool(true)])])])
        ]
        for value in invalid {
            do { _ = try await save.authorizationArguments(value); XCTFail("Invalid workflow must fail before approval") } catch {}
        }
        XCTAssertEqual(try store.all().count, 1)
    }
    func testLegacyWorkflowMigratesRevisionWithoutLosingIdentity() throws {
        let (store, defaults) = fixture()
        let id = UUID()
        let json: JSONValue = .array([.object(["id": .string(id.uuidString), "name": .string("Legacy"), "steps": .array([context])])])
        defaults.set(try JSONEncoder().encode(json), forKey: "personalWorkflows")
        let value = try XCTUnwrap(store.all().first)
        XCTAssertEqual(value.id, id); XCTAssertEqual(value.revision, 1)
        let updated = try store.upsert(value, expectedRevision: 1, registry: NativeTools.registry())
        XCTAssertEqual(updated.revision, 2)
    }
    func testCorruptStorageCannotBeOverwrittenBySave() throws {
        let (store, defaults) = fixture()
        let corrupt = Data("not JSON".utf8)
        defaults.set(corrupt, forKey: "personalWorkflows")
        XCTAssertThrowsError(try store.upsert(SavedWorkflow(name: "New", steps: .array([context])), expectedRevision: nil, registry: NativeTools.registry()))
        XCTAssertEqual(defaults.data(forKey: "personalWorkflows"), corrupt)
    }
    func testFrozenApprovalSequenceSurvivesEditsWithoutExecutingNewSteps() async throws {
        let (store, _) = fixture()
        let registry = NativeTools.registry()
        let first = try store.upsert(SavedWorkflow(name: "Study", steps: .array([context])), expectedRevision: nil, registry: registry)
        let run = WorkflowTool(registry: registry, store: store, journal: temporaryWorkflowJournal())
        let frozen = try await run.authorizationArguments(.object(["name": .string("Study"), "steps": .array([])]))
        let changed: JSONValue = .object(["tool": .string("timers.start"), "arguments": .object(["seconds": .number(600), "name": .string("Changed")])])
        _ = try store.upsert(SavedWorkflow(name: first.name, steps: .array([changed]), id: first.id), expectedRevision: 1, registry: registry)
        XCTAssertEqual(frozen.object?["steps"], .array([context]))
        XCTAssertEqual(frozen.object?["name"]?.string, "")
    }
    func testExactRoutineCommandsAndAmbiguity() {
        let first = SavedWorkflow(name: "Study session", steps: .array([context]))
        XCTAssertEqual(PersonalAutomation.workflow(for: "Start my study session.", workflows: [first])?.id, first.id)
        XCTAssertNil(PersonalAutomation.workflow(for: "Start my study session and delete files", workflows: [first]))
        let second = SavedWorkflow(name: "My study session", steps: .array([context]))
        XCTAssertNil(PersonalAutomation.workflow(for: "Run study session", workflows: [first, second]))
    }
    func testEditorPreservesSupportedActionsAndRejectsUnknownFields() throws {
        let values: [JSONValue] = [
            context,
            .object(["tool": .string("open_folder"), "arguments": .object(["path": .string("~/Documents")])]),
            .object(["tool": .string("files.open"), "arguments": .object(["path": .string("~/Documents/a.pdf")])]),
            .object(["tool": .string("apps.open"), "arguments": .object(["bundle_id": .string("com.apple.Notes")])]),
            .object(["tool": .string("audio.volume"), "arguments": .object(["action": .string("set"), "value": .string("30")])]),
            .object(["tool": .string("timers.start"), "arguments": .object(["seconds": .number(1500), "name": .string("Study")])]),
            .object(["tool": .string("audio.output"), "arguments": .object(["action": .string("select"), "device_id": .number(42)])]),
            .object(["tool": .string("system.openSettings"), "arguments": .object(["value": .string("Bluetooth")])])
        ]
        for value in values { XCTAssertEqual(try WorkflowEditorStep(value).json, value) }
        XCTAssertThrowsError(try WorkflowEditorStep(.object(["tool": .string("open_folder"), "arguments": .object(["path": .string("/tmp"), "extra": .string("must not disappear")])])))
    }
    func testSavingApprovalIsPlainLanguageAndDoesNotMutateArguments() {
        let value = args(steps: [.object(["tool": .string("timers.start"), "arguments": .object(["seconds": .number(1500), "name": .string("Study")])])])
        let request = Approval(tool: "workflows.save", arguments: value)
        let presentation = ApprovalPresentation(request)
        XCTAssertEqual(presentation.title, "Save workflow")
        XCTAssertEqual(presentation.fields.first?.value, "Study session")
        XCTAssertTrue(presentation.fields.contains { $0.label.contains("Start timer") && $0.value.contains("25") })
        XCTAssertEqual(request.arguments, value)
    }
}
