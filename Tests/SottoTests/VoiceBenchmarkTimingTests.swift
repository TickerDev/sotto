import XCTest
@testable import SottoAudio
@testable import SottoUI

@MainActor private final class DelayedStartupSpeech: SpeechRecognitionProvider {
    var ready: CheckedContinuation<Void, Never>?
    let entered: () -> Void
    init(entered: @escaping () -> Void) { self.entered = entered }
    func start(locale: String, deviceID: UInt32, onDevice: Bool, update: @escaping @Sendable (SpeechUpdate) -> Void) async {
        await withCheckedContinuation { ready = $0; entered() }
    }
    func finish() async throws -> String { "Fixture speech" }
    func cancel() { ready?.resume(); ready = nil }
}

final class VoiceBenchmarkTimingTests: XCTestCase, @unchecked Sendable {
    @MainActor func testReleaseDuringStartupIncludesRemainingStartupInFinalizationTiming() async throws {
        let entered = expectation(description: "Startup waiting"), finished = expectation(description: "Transcription complete")
        let speech = DelayedStartupSpeech { entered.fulfill() }
        let catalog = MicrophoneCatalog(observeHardware: false) {
            ([Microphone(uid: "fixture", deviceID: 12, name: "Fixture")], 12)
        }
        let app = AppModel(startServices: false, microphones: catalog, speech: speech)
        defer { app.shutdown() }
        app.present = { if app.voiceCheck == .passed { finished.fulfill() } }
        app.beginListening(purpose: .voiceCheck)
        await fulfillment(of: [entered], timeout: 1)
        app.endListening() // User releases before capture becomes ready.
        try await Task.sleep(for: .milliseconds(80))
        speech.ready?.resume(); speech.ready = nil
        await fulfillment(of: [finished], timeout: 1)
        let interval = try XCTUnwrap(app.voiceTimings["inputEndToFinalMs"])
        XCTAssertGreaterThanOrEqual(interval, 70, "Send-to-final timing must include startup after the user's release")
        XCTAssertNil(app.voiceTimings["activationToVerifiedCompletionMs"], "Transcription-only checks execute no action")
    }
}
