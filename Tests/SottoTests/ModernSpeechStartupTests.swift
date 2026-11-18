import XCTest
import Foundation
@testable import SottoAudio

private actor StartupLocaleGate {
    private var pending: [String: CheckedContinuation<Locale?, Never>] = [:]
    func resolve(_ name: String, entered: @Sendable () -> Void) async -> Locale? {
        await withCheckedContinuation { pending[name] = $0; entered() }
    }
    func release(_ name: String, locale: Locale? = nil) { pending.removeValue(forKey: name)?.resume(returning: locale) }
}
private actor StartupCaptureProbe: StreamingAudioCapture {
    private(set) var starts = 0
    func start(deviceID: UInt32, token: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) throws -> AsyncThrowingStream<Data, Error> {
        starts += 1
        XCTFail("Locale-only startup checks must never start capture")
        throw CancellationError()
    }
    func finish(_ token: SpeechSessionToken) {}
    func cancel(_ token: SpeechSessionToken) {}
}

final class ModernSpeechStartupTests: XCTestCase, @unchecked Sendable {
    func testCanceledLocaleLookupCannotResumeIntoCapture() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Modern speech requires macOS 26") }
        let gate = StartupLocaleGate(), capture = StartupCaptureProbe()
        let entered = expectation(description: "Locale lookup suspended")
        let worker = ModernSpeechWorker(microphone: capture, resolveLocale: { name in
            await gate.resolve(name) { entered.fulfill() }
        })
        let token = SpeechSessionToken()
        let startup = Task { try await worker.start(locale: "old", deviceID: 0, token: token) { _ in XCTFail("No updates after cancellation") } }
        await fulfillment(of: [entered], timeout: 1)
        await worker.cancel(token)
        await gate.release("old", locale: Locale(identifier: "en-US"))
        do { try await startup.value; XCTFail("Canceled lookup must fail") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let starts = await capture.starts
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(token.isActive)
    }

    func testStaleLookupCannotReplaceOrCancelNewStartup() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Modern speech requires macOS 26") }
        let gate = StartupLocaleGate(), capture = StartupCaptureProbe()
        let oldEntered = expectation(description: "Old locale lookup"), newEntered = expectation(description: "New locale lookup")
        let worker = ModernSpeechWorker(microphone: capture, resolveLocale: { name in
            await gate.resolve(name) { if name == "old" { oldEntered.fulfill() } else { newEntered.fulfill() } }
        })
        let old = SpeechSessionToken(), current = SpeechSessionToken()
        let first = Task { try await worker.start(locale: "old", deviceID: 0, token: old) { _ in XCTFail("No audio expected") } }
        await fulfillment(of: [oldEntered], timeout: 1)
        let second = Task { try await worker.start(locale: "new", deviceID: 0, token: current) { _ in XCTFail("No audio expected") } }
        await fulfillment(of: [newEntered], timeout: 1)
        await gate.release("old", locale: Locale(identifier: "en-US"))
        do { try await first.value; XCTFail("Replaced startup must fail") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(old.isActive)
        XCTAssertTrue(current.isActive, "Old cleanup must leave the new session active")
        await gate.release("new")
        do { try await second.value; XCTFail("Unsupported locale must fail") }
        catch SpeechError.recognitionUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(current.isActive, "Unsupported locale must clean up its session")
        let starts = await capture.starts
        XCTAssertEqual(starts, 0)
    }
}
