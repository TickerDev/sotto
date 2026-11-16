import XCTest
import SottoProviders
import SottoTools
import SottoSecurity
@testable import SottoUI

private actor SetupCredentials: CredentialStorage {
    var key: String? = "fixture-not-a-real-key"
    let failSave: Bool
    init(failSave: Bool = false) { self.failSave = failSave }
    func containsKey() -> Bool { key != nil }
    func read() -> String? { key }
    func save(_ key: String) throws {
        if failSave { throw ToolError.denied("Fixture Keychain save failed") }
        self.key = key
    }
}
private actor SetupProbe {
    var generations = 0
    var texts: [String] = []
    let completed: XCTestExpectation
    init(completed: XCTestExpectation) { self.completed = completed }
    func generate(_ input: [JSONValue]) {
        generations += 1
        texts = input.filter { $0.object?["role"]?.string == "user" }.compactMap { $0.object?["content"]?.string }
        completed.fulfill()
    }
}
private struct SetupProvider: ReasoningProvider {
    let probe: SetupProbe
    let verificationStarted: XCTestExpectation?
    let gate: SetupVerificationGate?
    func models() async throws -> [ModelInfo] {
        verificationStarted?.fulfill()
        await gate?.wait()
        return [ModelInfo(id: "gpt-4.1-mini", supportsTools: true)]
    }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                await probe.generate(input)
                c.yield(.text("Fixture response"))
                c.yield(.output([.object(["role": .string("assistant"), "content": .string("Fixture response")])]))
                c.finish()
            }
            c.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
private actor SetupVerificationGate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
final class IntelligenceSetupTests: XCTestCase, @unchecked Sendable {
    @MainActor func testPendingIntentRequiresVerificationExpiresAndCannotReplay() {
        let pending = PendingIntelligenceRequest()
        let start = ContinuousClock.now
        let id = pending.preserve("Original request", context: [.string("private context")], now: start)
        XCTAssertNil(pending.take(id, connectionVerified: false, now: start))
        XCTAssertNotNil(pending.intent)
        XCTAssertNil(pending.take(UUID(), connectionVerified: true, now: start))
        XCTAssertEqual(pending.take(id, connectionVerified: true, now: start)?.text, "Original request")
        XCTAssertNil(pending.take(id, connectionVerified: true, now: start))
        let expired = pending.preserve("Too old", context: [], now: start)
        XCTAssertNil(pending.take(expired, connectionVerified: true, now: start.advanced(by: .seconds(300))))
        XCTAssertNil(pending.intent)
        pending.preserve("Cancelled", context: [])
        pending.discard()
        XCTAssertNil(pending.intent)
    }
    @MainActor func testMissingIntelligencePreservesRequestWithoutGenerationOrConsent() async {
        let generated = expectation(description: "No generation"); generated.isInverted = true
        let probe = SetupProbe(completed: generated)
        let connection = ProviderConnection(credentials: SetupCredentials()) { _, _ in SetupProvider(probe: probe, verificationStarted: nil, gate: nil) }
        let app = AppModel(providerConnection: connection, preferences: Preferences(), startServices: false, onDeviceAvailable: { false })
        let offered = expectation(description: "Setup offered")
        app.openSettings = { offered.fulfill() }
        app.submit("Explain this request")
        await fulfillment(of: [offered], timeout: 2)
        XCTAssertTrue(app.intelligenceSetupPresented)
        XCTAssertEqual(app.pendingIntelligence.intent?.text, "Explain this request")
        XCTAssertFalse(app.settings.remoteConsent)
        await fulfillment(of: [generated], timeout: 0.05)
        app.shutdown()
        XCTAssertNil(app.pendingIntelligence.intent)
    }
    @MainActor func testLateVerificationAfterCancelCannotEnableCloudOrResume() async {
        let generated = expectation(description: "No generation after cancel"); generated.isInverted = true
        let started = expectation(description: "Verification started")
        let gate = SetupVerificationGate(), probe = SetupProbe(completed: generated)
        let connection = ProviderConnection(credentials: SetupCredentials()) { _, _ in SetupProvider(probe: probe, verificationStarted: started, gate: gate) }
        let app = AppModel(providerConnection: connection, preferences: Preferences(), startServices: false, onDeviceAvailable: { false })
        let offered = expectation(description: "Setup offered"); app.openSettings = { offered.fulfill() }
        app.submit("Explain this request")
        await fulfillment(of: [offered], timeout: 2)
        app.connectIntelligence(key: "", remoteConsent: true)
        await fulfillment(of: [started], timeout: 2)
        app.cancelIntelligenceSetup()
        await gate.release()
        await fulfillment(of: [generated], timeout: 0.05)
        XCTAssertFalse(app.settings.remoteConsent)
        XCTAssertNil(app.pendingIntelligence.intent)
        XCTAssertFalse(connection.verified)
        app.shutdown()
    }
    @MainActor func testFailedKeySaveDoesNotVerifyWithOldCredentials() async {
        let generated = expectation(description: "No generation"); generated.isInverted = true
        let verified = expectation(description: "No verification using old key"); verified.isInverted = true
        let probe = SetupProbe(completed: generated)
        let connection = ProviderConnection(credentials: SetupCredentials(failSave: true)) { _, _ in SetupProvider(probe: probe, verificationStarted: verified, gate: nil) }
        let app = AppModel(providerConnection: connection, preferences: Preferences(), startServices: false, onDeviceAvailable: { false })
        app.showIntelligenceSetup()
        app.connectIntelligence(key: "new-fixture", remoteConsent: true)
        await fulfillment(of: [verified, generated], timeout: 0.1)
        XCTAssertFalse(connection.lastSaveSucceeded)
        XCTAssertFalse(app.settings.remoteConsent)
        app.shutdown()
    }
    @MainActor func testVerifiedConnectionResumesOriginalRequestOnceAfterProviderChange() async {
        let generated = expectation(description: "Original request resumed once")
        generated.assertForOverFulfill = true
        let probe = SetupProbe(completed: generated)
        let connection = ProviderConnection(credentials: SetupCredentials()) { _, _ in SetupProvider(probe: probe, verificationStarted: nil, gate: nil) }
        var preferences = Preferences()
        preferences.automaticIntelligence = false; preferences.reasoningBackend = .ollama
        let app = AppModel(providerConnection: connection, preferences: preferences, startServices: false, onDeviceAvailable: { false })
        let offered = expectation(description: "Setup offered"); app.openSettings = { offered.fulfill() }
        app.submit("Explain this original request")
        await fulfillment(of: [offered], timeout: 2)
        app.connectIntelligence(key: "", remoteConsent: true)
        await fulfillment(of: [generated], timeout: 2)
        XCTAssertNil(app.pendingIntelligence.intent)
        XCTAssertTrue(app.settings.remoteConsent)
        XCTAssertFalse(app.settings.automaticIntelligence)
        XCTAssertEqual(app.settings.reasoningBackend, .openAI)
        XCTAssertTrue(connection.verified)
        let texts = await probe.texts
        XCTAssertEqual(texts, ["Explain this original request"])
        let count = await probe.generations
        XCTAssertEqual(count, 1)
        app.shutdown()
    }
    @MainActor func testConsentIsRequiredBeforeVerificationAndNewRequestDiscardsWaitingIntent() async {
        let generated = expectation(description: "No generation"); generated.isInverted = true
        let verified = expectation(description: "No verification without consent"); verified.isInverted = true
        let probe = SetupProbe(completed: generated)
        let connection = ProviderConnection(credentials: SetupCredentials()) { _, _ in SetupProvider(probe: probe, verificationStarted: verified, gate: nil) }
        let app = AppModel(providerConnection: connection, preferences: Preferences(), startServices: false, onDeviceAvailable: { false })
        let offered = expectation(description: "Setup offered"); app.openSettings = { offered.fulfill() }
        app.submit("Explain the first request")
        await fulfillment(of: [offered], timeout: 2)
        let oldID = app.pendingIntelligence.intent?.id
        app.connectIntelligence(key: "fixture", remoteConsent: false)
        await fulfillment(of: [verified, generated], timeout: 0.05)
        XCTAssertFalse(app.settings.remoteConsent)
        app.cancel()
        XCTAssertFalse(app.intelligenceSetupPresented)
        XCTAssertNil(app.pendingIntelligence.intent)
        if let oldID { XCTAssertNil(app.pendingIntelligence.take(oldID, connectionVerified: true)) }
        app.shutdown()
    }

}
