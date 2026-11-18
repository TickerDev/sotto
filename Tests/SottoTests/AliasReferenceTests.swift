import XCTest
@testable import SottoTools
@testable import SottoIntegrations

final class AliasReferenceTests: XCTestCase, @unchecked Sendable {
    private func fixture() -> (RememberedAliasStore, WorkflowStore, UserDefaults) {
        let suite = "SottoAliasTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (RememberedAliasStore(defaults: defaults), WorkflowStore(defaults: defaults), defaults)
    }
    func testLegacyFileAliasMigrationAndCorruptPreservation() throws {
        let (store, _, defaults) = fixture()
        let old: JSONValue = .array([.object(["name": .string("My résumé"), "path": .string("/tmp/resume.pdf")])])
        defaults.set(try JSONEncoder().encode(old), forKey: "rememberedAliases")
        let alias = try XCTUnwrap(store.all().first)
        XCTAssertEqual(alias.kind, .file); XCTAssertEqual(alias.revision, 1)
        let corrupt = Data("bad data".utf8)
        defaults.set(corrupt, forKey: "rememberedAliases")
        XCTAssertThrowsError(try store.upsert(alias, expectedRevision: 1))
        XCTAssertEqual(defaults.data(forKey: "rememberedAliases"), corrupt)
    }
    func testInstalledAppAndRenamedWorkflowReferencesPersistAndResolve() async throws {
        let (store, workflows, defaults) = fixture()
        let tool = AliasTool(action: "save", store: store, workflows: workflows)
        let app: JSONValue = .object(["name": .string("My browser"), "kind": .string("application"), "path": .string("com.apple.Safari")])
        let reviewed = try await tool.authorizationArguments(app)
        _ = try await tool.execute(arguments: reviewed)
        let restored = RememberedAliasStore(defaults: defaults)
        XCTAssertEqual(try restored.all().first?.kind, .application)
        let command = AliasCommand.resolve("Open my browser", aliases: try restored.all(), workflows: [])
        XCTAssertEqual(command?.tool, "apps.open")
        XCTAssertEqual(command?.arguments.object?["bundle_id"]?.string, "com.apple.Safari")
        let registry = NativeTools.registry()
        let steps: JSONValue = .array([.object(["tool": .string("screen.context"), "arguments": .object([:])])])
        let first = try workflows.upsert(SavedWorkflow(name: "Study", steps: steps), expectedRevision: nil, registry: registry)
        let routine: JSONValue = .object(["name": .string("My setup"), "kind": .string("workflow"), "path": .string(first.id.uuidString)])
        _ = try await tool.execute(arguments: try await tool.authorizationArguments(routine))
        _ = try workflows.upsert(SavedWorkflow(name: "Renamed study", steps: steps, id: first.id), expectedRevision: 1, registry: registry)
        let resolved = AliasCommand.resolve("Start my setup", aliases: try store.all(), workflows: try workflows.all())
        XCTAssertEqual(resolved?.tool, "workflows.run")
        XCTAssertEqual(resolved?.arguments.object?["name"]?.string, "Renamed study")
    }
    func testStaleChangesAndRemovalCannotOverwriteNewAssociation() throws {
        let (store, _, _) = fixture()
        let old = try store.upsert(RememberedAlias(name: "My app", path: "com.apple.Safari", kind: .application), expectedRevision: 0)
        let newer = try store.upsert(RememberedAlias(name: old.name, path: "com.apple.Notes", kind: .application), expectedRevision: 1)
        XCTAssertThrowsError(try store.remove(old))
        XCTAssertThrowsError(try store.upsert(old, expectedRevision: 1))
        XCTAssertEqual(try store.all().first, newer)
        try store.remove(newer); XCTAssertTrue(try store.all().isEmpty)
    }
    func testMissingTargetsAndAmbiguousNamesNeverChooseAnAction() async throws {
        let (store, workflows, _) = fixture()
        let tool = AliasTool(action: "save", store: store, workflows: workflows)
        do {
            _ = try await tool.authorizationArguments(.object(["name": .string("Missing"), "kind": .string("workflow"), "path": .string(UUID().uuidString)]))
            XCTFail("Unknown workflow must not be remembered")
        } catch {}
        let aliases = [RememberedAlias(name: "My app", path: "com.apple.Safari", kind: .application),
                       RememberedAlias(name: "App", path: "com.apple.Notes", kind: .application)]
        XCTAssertEqual(AliasCommand.resolve("Open my app", aliases: aliases, workflows: [])?.tool, "ask_user")
        XCTAssertNil(AliasCommand.resolve("Open my app and delete files", aliases: aliases, workflows: []))
    }
}

@testable import SottoAgent

final class AliasDocumentScopeTests: XCTestCase {
    func testOnlyExplicitlyNamedApprovedFileAliasCanAuthorizeRead() throws {
        var scope = DocumentReadScope()
        let aliases = ToolResult("Names", data: .array([
            .object(["name": .string("My résumé"), "path": .string("/tmp/resume.pdf"), "kind": .string("file")]),
            .object(["name": .string("Private notes"), "path": .string("/tmp/private.txt"), "kind": .string("file")]),
            .object(["name": .string("Research"), "path": .string("/tmp/research"), "kind": .string("folder")])
        ]))
        scope.recordAliases(aliases, request: "Summarize my resume")
        XCTAssertNoThrow(try scope.validate(.object(["path": .string("/tmp/resume.pdf")]), request: "Summarize my resume"))
        XCTAssertThrowsError(try scope.validate(.object(["path": .string("/tmp/private.txt")]), request: "Summarize my resume"))
        XCTAssertThrowsError(try scope.validate(.object(["path": .string("/tmp/research/secret.txt")]), request: "Summarize my resume"))
    }
}
