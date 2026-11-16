import XCTest
@testable import SottoUI
@testable import SottoSecurity
import SottoProviders
import SottoTools

private actor VerificationGate {
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async { if !released { await withCheckedContinuation { waiting.append($0) } } }
    func release() { released = true; let pending = waiting; waiting = []; pending.forEach { $0.resume() } }
}
private actor VerificationCredentials: CredentialStorage {
    var key: String? = "test-fixture-not-a-real-key"
    let gate: VerificationGate?
    let started: (@Sendable () -> Void)?
    var metadataGate: VerificationGate?
    var metadataStarted: (@Sendable () -> Void)?
    init(gate: VerificationGate? = nil, started: (@Sendable () -> Void)? = nil) { self.gate = gate; self.started = started }
    func configureMetadata(gate: VerificationGate, started: @escaping @Sendable () -> Void) { metadataGate = gate; metadataStarted = started }
    func containsKey() async -> Bool { metadataStarted?(); await metadataGate?.wait(); return key != nil }
    func read() async -> String? { started?(); await gate?.wait(); return key }
    func save(_ key: String) { self.key = key.isEmpty ? nil : key }
}
private struct VerificationProvider: ReasoningProvider {
    let id: String
    var gate: VerificationGate?
    var started: (@Sendable () -> Void)?
    var fails = false
    func models() async throws -> [ModelInfo] {
        started?(); await gate?.wait()
        if fails { throw ToolError.denied("Test authentication failure") }
        return [ModelInfo(id: id, supportsTools: true)]
    }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> { AsyncThrowingStream { $0.finish() } }
}
final class ProviderConnectionTests: XCTestCase, @unchecked Sendable {
    @MainActor func testVerificationSuccessAndFailureAreDisplayedWithoutTerminating() async {
        let credentials = VerificationCredentials()
        let ok = ProviderConnection(credentials: credentials) { _, model in VerificationProvider(id: model) }
        await ok.inspectSavedKey(); XCTAssertTrue(ok.hasSavedKey)
        await ok.verify(model: "gpt-4.1-mini")
        XCTAssertTrue(ok.verified); XCTAssertFalse(ok.isChecking); XCTAssertEqual(ok.status, "Connected · gpt-4.1-mini")
        let failed = ProviderConnection(credentials: credentials) { _, model in VerificationProvider(id: model, fails: true) }
        await failed.verify(model: "gpt-4.1-mini")
        XCTAssertFalse(failed.verified); XCTAssertFalse(failed.isChecking); XCTAssertEqual(failed.status, "Test authentication failure")
    }
    @MainActor func testCancelDuringKeychainReadKeepsUIResponsiveAndIgnoresLateResult() async {
        let gate = VerificationGate(); let started = expectation(description: "Reading credentials")
        let credentials = VerificationCredentials(gate: gate, started: { started.fulfill() })
        let connection = ProviderConnection(credentials: credentials) { _, model in VerificationProvider(id: model) }
        let task = Task { await connection.verify(model: "gpt-4.1-mini") }
        await fulfillment(of: [started], timeout: 2)
        MainActor.assertIsolated()
        XCTAssertTrue(connection.isChecking)
        connection.cancelVerification()
        XCTAssertFalse(connection.isChecking); XCTAssertEqual(connection.status, "Verification cancelled")
        await gate.release(); await task.value
        XCTAssertFalse(connection.verified); XCTAssertEqual(connection.status, "Verification cancelled")
    }
    @MainActor func testOlderNetworkResultCannotReplaceNewVerification() async {
        let gate = VerificationGate(); let started = expectation(description: "Old request started")
        let connection = ProviderConnection(credentials: VerificationCredentials()) { _, model in
            if model == "old-model" { return VerificationProvider(id: model, gate: gate, started: { started.fulfill() }) }
            return VerificationProvider(id: model)
        }
        let old = Task { await connection.verify(model: "old-model") }
        await fulfillment(of: [started], timeout: 2)
        connection.cancelVerification()
        await connection.verify(model: "new-model")
        XCTAssertTrue(connection.verified)
        await gate.release(); await old.value
        XCTAssertEqual(connection.status, "Connected · new-model"); XCTAssertEqual(connection.models.first?.id, "new-model")
    }
    @MainActor func testLateStartupInspectionCannotHideVerificationFailure() async {
        let gate = VerificationGate(); let started = expectation(description: "Metadata inspection started")
        let credentials = VerificationCredentials()
        await credentials.configureMetadata(gate: gate, started: { started.fulfill() })
        let connection = ProviderConnection(credentials: credentials) { _, model in VerificationProvider(id: model, fails: true) }
        let inspection = Task { await connection.inspectSavedKey() }
        await fulfillment(of: [started], timeout: 2)
        await connection.verify(model: "gpt-4.1-mini")
        await gate.release(); await inspection.value
        XCTAssertEqual(connection.status, "Test authentication failure"); XCTAssertFalse(connection.verified)
    }
    @MainActor func testDisconnectCancelsVerificationAndActuallyRemovesCredential() async {
        let gate = VerificationGate(); let started = expectation(description: "Request started")
        let credentials = VerificationCredentials()
        let connection = ProviderConnection(credentials: credentials) { _, model in VerificationProvider(id: model, gate: gate, started: { started.fulfill() }) }
        let task = Task { await connection.verify(model: "gpt-4.1-mini") }
        await fulfillment(of: [started], timeout: 2)
        let write = connection.saveKey(""); await write.value
        await gate.release(); await task.value
        let exists = await credentials.containsKey()
        XCTAssertFalse(exists); XCTAssertFalse(connection.hasSavedKey); XCTAssertFalse(connection.verified); XCTAssertEqual(connection.status, "Not connected")
    }
    @MainActor func testSecurityWorkRunsOffMainThreadAndStartupInspectionDoesNotReadSecret() async throws {
        let entered = expectation(description: "Worker entered")
        let release = DispatchSemaphore(value: 0)
        let store = KeychainCredentials(read: {
            XCTAssertFalse(Thread.isMainThread)
            entered.fulfill()
            _ = release.wait(timeout: .now() + 3)
            return "fixture"
        }, save: { _ in XCTAssertFalse(Thread.isMainThread) }, contains: {
            XCTAssertFalse(Thread.isMainThread)
            return true
        })
        let present = try await store.containsKey(); XCTAssertTrue(present)
        let read = Task { try await store.read() }
        await fulfillment(of: [entered], timeout: 2)
        MainActor.assertIsolated()
        release.signal()
        let value = try await read.value; XCTAssertEqual(value, "fixture")
        try await store.save("fixture")
    }
}
