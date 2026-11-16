import XCTest
import SottoAudio
@testable import SottoUI

@MainActor private final class InputInventory {
    var devices: [Microphone]
    var defaultID: UInt32
    init(_ devices: [Microphone], defaultID: UInt32) { self.devices = devices; self.defaultID = defaultID }
    func catalog() -> MicrophoneCatalog { MicrophoneCatalog(observeHardware: false) { [self] in (devices, defaultID) } }
}
@MainActor private final class AdaptiveSpeechProbe: SpeechRecognitionProvider {
    var starts: [UInt32] = []
    var finishes = 0
    var failing: Set<UInt32> = []
    var denied = false
    var started: ((UInt32) -> Void)?
    var update: (@Sendable (SpeechUpdate) -> Void)?
    func start(locale: String, deviceID: UInt32, onDevice: Bool, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        starts.append(deviceID); self.update = update; started?(deviceID)
        if denied { throw SpeechError.microphonePermission }
        if failing.contains(deviceID) { throw SpeechError.microphoneUnavailable("Fixture input unavailable") }
    }
    func finish() async throws -> String { finishes += 1; return "Fixture speech" }
    func cancel() { update = nil }
}
final class AdaptiveMicrophoneTests: XCTestCase, @unchecked Sendable {
    let builtIn = Microphone(uid: "builtin", deviceID: 12, name: "Mac microphone")
    let headset = Microphone(uid: "headset", deviceID: 42, name: "Headset")
    func testPreferredThenSystemThenRemainingAndExplicitExclusions() throws {
        let devices = [headset, builtIn]
        XCTAssertEqual(try Microphones.resolve(uid: "headset", devices: devices, defaultInputID: 12), headset)
        XCTAssertEqual(try Microphones.resolve(uid: "missing", devices: devices, defaultInputID: 12), builtIn)
        XCTAssertEqual(try Microphones.resolve(uid: "headset", devices: devices, defaultInputID: 42, excluding: ["headset"]), builtIn)
        XCTAssertEqual(try Microphones.resolve(uid: "", devices: [builtIn], defaultInputID: 999), builtIn)
        XCTAssertThrowsError(try Microphones.resolve(uid: "headset", devices: devices, defaultInputID: 42, excluding: ["headset", "builtin"]))
        XCTAssertThrowsError(try Microphones.resolve(uid: "", devices: [], defaultInputID: 0))
    }
    @MainActor func testDisconnectRestartsOnFallbackAndIgnoresOldTranscript() async {
        let inventory = InputInventory([headset, builtIn], defaultID: 42)
        let catalog = inventory.catalog(), speech = AdaptiveSpeechProbe()
        var preferences = Preferences(); preferences.microphoneUID = "headset"
        let app = AppModel(preferences: preferences, startServices: false, microphones: catalog, speech: speech)
        defer { app.shutdown() }
        let first = expectation(description: "Preferred input starts")
        let fallback = expectation(description: "Fallback starts")
        speech.started = { id in if id == 42 { first.fulfill() } else if id == 12 { fallback.fulfill() } }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [first], timeout: 2)
        let staleCallback = speech.update
        inventory.devices = [builtIn]; inventory.defaultID = 12; catalog.refresh()
        await fulfillment(of: [fallback], timeout: 2)
        staleCallback?(.transcript("incomplete old command"))
        await Task.yield()
        XCTAssertEqual(speech.starts, [42, 12])
        XCTAssertEqual(speech.finishes, 0)
        XCTAssertEqual(app.transcript, "")
        XCTAssertTrue(app.status.contains("Please repeat"))
        XCTAssertEqual(app.settings.microphoneUID, "headset", "Keep the preference for the next activation")
        inventory.devices = [headset, builtIn]; inventory.defaultID = 42; catalog.refresh()
        XCTAssertEqual(speech.starts, [42, 12], "Do not interrupt a working recording when the preferred input returns")
        let preferredAgain = expectation(description: "Preference restored on next activation")
        speech.started = { if $0 == 42 { preferredAgain.fulfill() } }
        app.cancel(); app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [preferredAgain], timeout: 2)
        XCTAssertEqual(speech.starts, [42, 12, 42])
    }
    @MainActor func testStartupFailureTriesAnotherAvailableInput() async {
        let inventory = InputInventory([headset, builtIn], defaultID: 42)
        let speech = AdaptiveSpeechProbe(); speech.failing = [42]
        let app = AppModel(startServices: false, microphones: inventory.catalog(), speech: speech)
        defer { app.shutdown() }
        let fallback = expectation(description: "Working fallback starts")
        speech.started = { if $0 == 12 { fallback.fulfill() } }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [fallback], timeout: 2)
        XCTAssertEqual(speech.starts, [42, 12])
        XCTAssertEqual(speech.finishes, 0)
    }
    @MainActor func testRecoveryStopsAfterBoundedAttemptsAndCancelCannotRestartCapture() async {
        let inventory = InputInventory([builtIn], defaultID: 12)
        let speech = AdaptiveSpeechProbe(); speech.failing = [12]
        let app = AppModel(startServices: false, microphones: inventory.catalog(), speech: speech)
        defer { app.shutdown() }
        let stopped = expectation(description: "Unstable input stops")
        app.present = { if app.state == .failed { stopped.fulfill() } }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(speech.starts.count, 3)
        XCTAssertEqual(speech.finishes, 0)
        let before = speech.starts.count
        app.cancel(); inventory.devices = [headset, builtIn]; inventory.defaultID = 42
        app.microphones.refresh()
        XCTAssertEqual(speech.starts.count, before)
    }
    @MainActor func testPermissionDenialDoesNotTryOtherMicrophones() async {
        let inventory = InputInventory([headset, builtIn], defaultID: 42)
        let speech = AdaptiveSpeechProbe(); speech.denied = true
        let app = AppModel(startServices: false, microphones: inventory.catalog(), speech: speech)
        defer { app.shutdown() }
        let stopped = expectation(description: "Permission denial stops capture")
        app.present = { if app.state == .failed { stopped.fulfill() } }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(speech.starts, [42])
        XCTAssertEqual(speech.finishes, 0)
    }
    @MainActor func testCancelledInputFailureCallbackCannotResumeRecording() async {
        let inventory = InputInventory([headset, builtIn], defaultID: 42)
        let speech = AdaptiveSpeechProbe()
        let app = AppModel(startServices: false, microphones: inventory.catalog(), speech: speech)
        defer { app.shutdown() }
        let started = expectation(description: "Recording starts")
        speech.started = { _ in started.fulfill() }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [started], timeout: 2)
        let stale = speech.update
        app.cancel()
        let noRestart = expectation(description: "No restart after cancel"); noRestart.isInverted = true
        speech.started = { _ in noRestart.fulfill() }
        stale?(.inputUnavailable("Fixture device lost"))
        await fulfillment(of: [noRestart], timeout: 0.05)
        XCTAssertEqual(speech.starts, [42])
        XCTAssertEqual(app.state, .idle)
    }
    @MainActor func testNoInputStopsWithoutStartingSpeech() async {
        let inventory = InputInventory([], defaultID: 0), speech = AdaptiveSpeechProbe()
        let app = AppModel(startServices: false, microphones: inventory.catalog(), speech: speech)
        defer { app.shutdown() }
        let stopped = expectation(description: "No available microphone")
        app.present = { if app.state == .failed { stopped.fulfill() } }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertTrue(speech.starts.isEmpty)
        XCTAssertTrue(app.reply.contains("No microphone"))
    }
    @MainActor func testExplicitlySelectedMicrophoneRetriesBeforeFallingBackToHeadset() async {
        let inventory = InputInventory([headset, builtIn], defaultID: 42)
        let speech = AdaptiveSpeechProbe(); speech.failing = [12]
        var preferences = Preferences(); preferences.microphoneUID = "builtin"
        let app = AppModel(preferences: preferences, startServices: false, microphones: inventory.catalog(), speech: speech)
        defer { app.shutdown() }
        let recovered = expectation(description: "Recovered on preferred microphone")
        var attempts = 0
        speech.started = { id in
            attempts += 1
            if attempts == 1 { Task { @MainActor in speech.failing = [] } }
            else if attempts == 2 && id == 12 { recovered.fulfill() }
        }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [recovered], timeout: 2)
        XCTAssertEqual(speech.starts, [12, 12], "Retry still-present Mac microphone before falling back to headset")

        // If the preferred microphone fails again after retrying, fall back to another input.
        app.cancel()
        speech.starts = []; speech.failing = [12]
        let fallback = expectation(description: "Falls back after preferred retry also fails")
        speech.started = { id in if id == 42 { fallback.fulfill() } }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [fallback], timeout: 2)
        XCTAssertEqual(speech.starts, [12, 12, 42])
    }

}
