import XCTest
import SottoAgent
import SottoTools
import SottoSecurity
import SottoUI
import SottoIntegrations

private actor NativeProbe {
    var executions = 0
    func increment() { executions += 1 }
}
private struct NativeFolderProbe: Tool {
    let probe: NativeProbe
    let descriptor = ToolDescriptor(id: "open_folder", description: "Open folder", properties: ["path": textProperty("Path")], required: ["path"], risk: .reversible, capabilities: [.files])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        await probe.increment()
        return ToolResult("Opened Downloads in Finder")
    }
}
private actor ConnectionProbe {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(started: @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started()
        }
    }
    func allow() { continuation?.resume(); continuation = nil }
}
final class AutomaticIntelligenceTests: XCTestCase, @unchecked Sendable {
    func testDefaultIsAutomaticWithoutRemoteConsentAndMigrationPreservesManualChoice() throws {
        XCTAssertTrue(Preferences().automaticIntelligence)
        XCTAssertFalse(Preferences().remoteConsent)
        let readiness = SetupReadiness(providerConnected: false, remoteConsent: false, voiceAllowed: false, microphoneAvailable: false, shortcutReady: false, nativeActionsAvailable: true)
        XCTAssertTrue(readiness.ready)
        XCTAssertFalse(readiness.providerConnected)
        XCTAssertTrue(readiness.blockers.isEmpty)
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"reasoningBackend":"ollama","ollamaModel":"existing"}"#.utf8))
        XCTAssertFalse(legacy.automaticIntelligence)
        XCTAssertEqual(legacy.ollamaModel, "existing")
        let roundTrip = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(Preferences()))
        XCTAssertTrue(roundTrip.automaticIntelligence)
    }
    func testBoundedGrammarRejectsCompoundOrAmbiguousCommands() {
        XCTAssertNotNil(NativeCommandProvider(command: "Open my Downloads folder."))
        XCTAssertNotNil(NativeCommandProvider(command: "Find my latest PDF"))
        for command in ["open my downloads and delete everything", "don't open downloads", "open my folder", "remind me tomorrow", "Open my Downloads folder. Then send it to someone"] {
            XCTAssertNil(NativeCommandProvider(command: command), command)
        }
    }
    func testNativeExecutionUsesRuntimeAndReturnsRealToolEvidenceOnce() async throws {
        let probe = NativeProbe()
        let runtime = AgentRuntime(registry: ToolRegistry([NativeFolderProbe(probe: probe)]), gate: AuthorizationGate())
        let provider = try XCTUnwrap(NativeCommandProvider(command: "Open my Downloads folder"))
        let context = try await runtime.run("Open my Downloads folder", provider: provider) { _ in }
        let count = await probe.executions
        XCTAssertEqual(count, 1)
        XCTAssertTrue(context.contains { $0.object?["type"]?.string == "function_call_output" && $0.object?["output"]?.string?.contains("Opened Downloads") == true })
    }
    func testDeclinedIntegrationDoesNotExecuteOrRetry() async throws {
        let probe = NativeProbe()
        let runtime = AgentRuntime(registry: ToolRegistry([NativeFolderProbe(probe: probe)]), gate: AuthorizationGate())
        do {
            _ = try await runtime.run("Open Downloads", provider: XCTUnwrap(NativeCommandProvider(command: "open downloads")), prepare: { _ in throw IntegrationAccessError.cancelled }) { _ in }
            XCTFail("Declined access must end the request")
        } catch IntegrationAccessError.cancelled {}
        let count = await probe.executions
        XCTAssertEqual(count, 0)
    }
    func testAuthorizationResumesSameRequestExactlyOnce() async throws {
        let probe = NativeProbe(), connection = ConnectionProbe()
        let waiting = expectation(description: "Authorization is pending")
        let runtime = AgentRuntime(registry: ToolRegistry([NativeFolderProbe(probe: probe)]), gate: AuthorizationGate())
        let provider = try XCTUnwrap(NativeCommandProvider(command: "open downloads"))
        let task = Task {
            try await runtime.run("open downloads", provider: provider, prepare: { _ in
                await connection.wait { waiting.fulfill() }
            }) { _ in }
        }
        await fulfillment(of: [waiting], timeout: 2)
        let before = await probe.executions
        XCTAssertEqual(before, 0)
        await connection.allow()
        let context = try await task.value
        let after = await probe.executions
        XCTAssertEqual(after, 1)
        XCTAssertEqual(context.filter { $0.object?["role"]?.string == "user" }.count, 1)
    }
    func testLiveProviderFreeDownloads() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_NATIVE_TEST"] == "1" else { throw XCTSkip("Opt-in: opens Downloads in Finder; no AI account or network") }
        let runtime = AgentRuntime(registry: NativeTools.registry(), gate: AuthorizationGate())
        let provider = try XCTUnwrap(NativeCommandProvider(command: "Open my Downloads folder"))
        let context = try await runtime.run("Open my Downloads folder", provider: provider) { _ in }
        let results = context.filter { $0.object?["type"]?.string == "function_call_output" }.compactMap { $0.object?["output"]?.string }
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first?.contains("Opened Downloads in Finder") == true)
    }

}
