import XCTest
@testable import SottoUI
import SottoTools
import SottoProviders

@MainActor private final class RuntimeProcessProbe: LocalRuntimeProcess {
    var running = false
    var launches = 0
    var stops = 0
    var environment: [String: String] = [:]
    func launch(executable: URL, environment: [String: String]) throws {
        launches += 1; running = true; self.environment = environment
    }
    func stop() { stops += 1; running = false }
}
private actor RuntimeReadinessProbe {
    var checks = 0
    let readyAfter: Int
    init(readyAfter: Int) { self.readyAfter = readyAfter }
    func ready() -> Bool { checks += 1; return checks >= readyAfter }
}
final class ManagedOllamaRuntimeTests: XCTestCase, @unchecked Sendable {
    let endpoint = "http://127.0.0.1:11434"
    @MainActor func testAlreadyRunningServerIsReusedAndNeverStopped() async throws {
        let process = RuntimeProcessProbe()
        let runtime = ManagedOllamaRuntime(executable: { nil }, makeProcess: { process }, probe: { _ in true })
        try await runtime.ensureRunning(endpoint: endpoint)
        XCTAssertFalse(runtime.ownsRunningProcess)
        runtime.shutdown()
        XCTAssertEqual(process.launches, 0); XCTAssertEqual(process.stops, 0)
    }
    @MainActor func testStartsLocalOnlyEngineAndStopsOnlyOwnedChild() async throws {
        let process = RuntimeProcessProbe(), readiness = RuntimeReadinessProbe(readyAfter: 3)
        let runtime = ManagedOllamaRuntime(executable: { URL(fileURLWithPath: "/fixture/ollama") }, makeProcess: { process }, probe: { _ in await readiness.ready() }, pause: { try Task.checkCancellation() })
        try await runtime.ensureRunning(endpoint: endpoint)
        XCTAssertEqual(process.launches, 1)
        XCTAssertTrue(runtime.ownsRunningProcess)
        XCTAssertEqual(process.environment["OLLAMA_HOST"], "127.0.0.1:11434")
        XCTAssertEqual(process.environment["OLLAMA_NO_CLOUD"], "1")
        XCTAssertNil(process.environment["OPENAI_API_KEY"])
        try await runtime.ensureRunning(endpoint: endpoint)
        XCTAssertEqual(process.launches, 1)
        runtime.shutdown()
        XCTAssertEqual(process.stops, 1)
    }
    @MainActor func testTimeoutTerminatesOwnedChildAndReportsFailure() async {
        let process = RuntimeProcessProbe()
        let runtime = ManagedOllamaRuntime(executable: { URL(fileURLWithPath: "/fixture/ollama") }, makeProcess: { process }, probe: { _ in false }, attempts: 2, pause: { try Task.checkCancellation() })
        do { try await runtime.ensureRunning(endpoint: endpoint); XCTFail("Unready engine accepted") } catch {}
        XCTAssertEqual(process.launches, 1); XCTAssertEqual(process.stops, 1)
        XCTAssertFalse(runtime.starting); XCTAssertFalse(runtime.ownsRunningProcess)
    }
    @MainActor func testNoExecutableOrCustomEndpointNeverLaunchesCommands() async {
        let process = RuntimeProcessProbe()
        let missing = ManagedOllamaRuntime(executable: { nil }, makeProcess: { process }, probe: { _ in false })
        do { try await missing.ensureRunning(endpoint: endpoint); XCTFail("Missing engine accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Install")) }
        let custom = ManagedOllamaRuntime(executable: { URL(fileURLWithPath: "/fixture/ollama") }, makeProcess: { process }, probe: { _ in false })
        for address in ["http://127.0.0.1:12345", "http://example.com:11434"] {
            do { try await custom.ensureRunning(endpoint: address); XCTFail("Custom server spawned unexpectedly") } catch {}
        }
        XCTAssertEqual(process.launches, 0)
    }
    @MainActor func testShutdownDuringStartupIgnoresLateReadiness() async {
        let process = RuntimeProcessProbe(), readiness = RuntimeReadinessProbe(readyAfter: 99)
        let waiting = expectation(description: "Child startup is waiting")
        let runtime = ManagedOllamaRuntime(executable: { URL(fileURLWithPath: "/fixture/ollama") }, makeProcess: { process }, probe: { _ in await readiness.ready() }, pause: {
            waiting.fulfill()
            try await Task.sleep(for: .seconds(5))
        })
        let task = Task { try await runtime.ensureRunning(endpoint: endpoint) }
        await fulfillment(of: [waiting], timeout: 2)
        runtime.shutdown()
        do { try await task.value; XCTFail("Cancelled startup reported ready") } catch {}
        XCTAssertFalse(runtime.starting); XCTAssertFalse(runtime.ownsRunningProcess)
        XCTAssertEqual(process.stops, 1)
    }
    @MainActor func testIdleShutdownWaitsForRequestLease() async throws {
        let process = RuntimeProcessProbe(), readiness = RuntimeReadinessProbe(readyAfter: 2)
        let runtime = ManagedOllamaRuntime(executable: { URL(fileURLWithPath: "/fixture/ollama") }, makeProcess: { process }, probe: { _ in await readiness.ready() }, idleDuration: .milliseconds(10), pause: { try Task.checkCancellation() })
        runtime.beginUse()
        try await runtime.ensureRunning(endpoint: endpoint)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(process.running)
        runtime.endUse()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(process.running)
        XCTAssertEqual(process.stops, 1)
    }
    @MainActor func testLiveInstalledRuntimeReusesExistingServerAndVerifiesCatalog() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_RUNTIME_TEST"] == "1" else { throw XCTSkip("Opt-in: starts an installed engine if needed; no model downloads or generation") }
        let runtime = ManagedOllamaRuntime()
        defer { runtime.shutdown() }
        let wasAlreadyRunning = await ManagedOllamaRuntime.probe(endpoint)
        try await runtime.ensureRunning(endpoint: endpoint)
        XCTAssertTrue(awaitReady(runtime))
        let models = try await OllamaProvider(model: "").models()
        XCTAssertFalse(models.isEmpty, "Live fixture requires an installed model")
        XCTAssertTrue(models.contains(where: \.supportsTools))
        if wasAlreadyRunning {
            XCTAssertFalse(runtime.ownsRunningProcess)
            runtime.shutdown()
            let stillRunning = await ManagedOllamaRuntime.probe(endpoint)
            XCTAssertTrue(stillRunning, "Existing server must survive Sotto shutdown")
        }
    }
    @MainActor private func awaitReady(_ runtime: ManagedOllamaRuntime) -> Bool { runtime.status == "Ready on this Mac" }

    @MainActor func testLiveOwnedEngineStartsAndStopsOnIsolatedLoopbackPort() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_RUNTIME_TEST"] == "1" else { throw XCTSkip("Opt-in: launches installed Ollama on an isolated port; no downloads or inference") }
        let binary = try XCTUnwrap(ManagedOllamaRuntime.installedExecutable())
        let address = "http://127.0.0.1:51567"
        guard !(await ManagedOllamaRuntime.probe(address)) else { throw XCTSkip("Live fixture port is already serving Ollama") }
        let process = OllamaChildProcess()
        defer { process.stop() }
        try process.launch(executable: binary, environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": NSTemporaryDirectory(), "OLLAMA_HOST": "127.0.0.1:51567", "OLLAMA_NO_CLOUD": "1", "OLLAMA_KEEP_ALIVE": "1m"])
        var ready = false
        for _ in 0..<40 {
            if await ManagedOllamaRuntime.probe(address) { ready = true; break }
            guard process.running else { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertTrue(ready, "Real managed child did not become ready")
        guard ready else { return }
        let catalog = try await OllamaProvider(endpoint: address, model: "").models()
        XCTAssertTrue(catalog.contains(where: \.supportsTools))
        process.stop()
        for _ in 0..<20 {
            if !process.running { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(process.running, "Owned process should terminate after stop")
    }

}
