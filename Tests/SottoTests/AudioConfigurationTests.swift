import AVFoundation
import SottoAudioBridge
import XCTest
@testable import SottoAudio

final class AudioConfigurationTests: XCTestCase {
    func configuration(device: UInt32 = 42, rate: Double = 48000, channels: UInt32 = 1) -> AudioInputConfiguration {
        AudioInputConfiguration(deviceID: device, sampleRate: rate, channels: channels, formatID: 1819304813, formatFlags: 9, bytesPerFrame: 4 * channels, bitsPerChannel: 32)
    }
    func testUnchangedRunningInputDoesNotDiscardOrConsumeRepairBudget() {
        var policy = AudioConfigurationGuard(expected: configuration())
        for _ in 0..<20 { XCTAssertEqual(policy.evaluate(current: configuration(), running: true, hasAudio: true), .ignore) }
        XCTAssertEqual(policy.repairsRemaining, 2)
    }
    func testStoppedEngineWithSameInputCanResumeWithoutResettingSpeech() {
        var policy = AudioConfigurationGuard(expected: configuration())
        XCTAssertEqual(policy.evaluate(current: configuration(), running: false, hasAudio: true), .restart)
        XCTAssertEqual(policy.evaluate(current: configuration(), running: true, hasAudio: true), .ignore)
    }
    func testInitialHardwareFormatSettlingCanRebuildBeforeFirstBuffer() {
        var policy = AudioConfigurationGuard(expected: configuration())
        let headset = configuration(rate: 16000)
        XCTAssertEqual(policy.evaluate(current: headset, running: false, hasAudio: false), .rebuildStartupTap)
        XCTAssertEqual(policy.expected, headset)
        XCTAssertEqual(policy.evaluate(current: headset, running: true, hasAudio: true), .ignore)
    }
    func testFormatChangesAfterAudioArrivesStillDiscard() {
        for changed in [configuration(rate: 16000), configuration(channels: 2)] {
            var policy = AudioConfigurationGuard(expected: configuration())
            XCTAssertEqual(policy.evaluate(current: changed, running: true, hasAudio: true), .discard)
        }
    }
    func testDifferentDeviceNeverSilentlyReplacesSelectedMicrophone() {
        for hasAudio in [false, true] {
            var policy = AudioConfigurationGuard(expected: configuration())
            XCTAssertEqual(policy.evaluate(current: configuration(device: 99), running: true, hasAudio: hasAudio), .discard)
        }
    }
    func testMissingOrInvalidInputDiscardsInsteadOfGuessing() {
        for current in [nil, configuration(device: 0), configuration(rate: 0), configuration(rate: .nan), configuration(channels: 0)] {
            var policy = AudioConfigurationGuard(expected: configuration())
            XCTAssertEqual(policy.evaluate(current: current, running: false, hasAudio: false), .discard)
        }
    }
    func testUnstableNotificationLoopHasBoundedRecovery() {
        var policy = AudioConfigurationGuard(expected: configuration())
        XCTAssertEqual(policy.evaluate(current: configuration(), running: false, hasAudio: false), .restart)
        XCTAssertEqual(policy.evaluate(current: configuration(), running: false, hasAudio: false), .restart)
        XCTAssertEqual(policy.evaluate(current: configuration(), running: false, hasAudio: false), .discard)
    }
    func testFirstAudioTrackingDoesNotAcceptBuffersAfterCancel() {
        let session = SpeechSessionToken()
        XCTAssertFalse(session.hasAudio)
        XCTAssertEqual(session.acceptBuffer(), true)
        XCTAssertTrue(session.hasAudio)
        XCTAssertEqual(session.acceptBuffer(), false)
        session.cancel()
        XCTAssertNil(session.acceptBuffer())
    }
    func testCaptureInputConfiguresSelectedDeviceWithOutputDisabled() throws {
        let devices = Microphones.available()
        let defaultID = Microphones.defaultInputID()
        guard let target = devices.first(where: { $0.deviceID == defaultID }) ?? devices.first else {
            throw XCTSkip("No physical microphone in this environment")
        }
        let engine = AVAudioEngine()
        let config = try CaptureInput.configure(engine, deviceID: target.deviceID)
        XCTAssertEqual(config.deviceID, target.deviceID)
        XCTAssertTrue(config.isUsable)
        XCTAssertFalse(engine.inputNode.auAudioUnit.isOutputEnabled)
        XCTAssertTrue(engine.inputNode.auAudioUnit.isInputEnabled)
        XCTAssertNil(SottoInstallMicrophoneTap(engine.inputNode) { _, _ in })
        defer { _ = SottoStopAudioEngine(engine, true) }
        XCTAssertNil(SottoStartAudioEngine(engine))
        XCTAssertTrue(engine.isRunning)
    }
}
