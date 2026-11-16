import XCTest
@testable import SottoAudio

final class SpeechSessionTests: XCTestCase, @unchecked Sendable {
    @MainActor func testRealStartupMethodEntersAudioActorOffMainThread() async {
        let entered = expectation(description: "Worker startup executes away from UI")
        let worker = AppleSpeechWorker {
            XCTAssertFalse(Thread.isMainThread)
            entered.fulfill()
        }
        let session = SpeechSessionToken(); session.cancel()
        do {
            try await worker.start(locale: "en-US", deviceID: 0, onDevice: true, session: session) { _ in XCTFail("Canceled startup must not produce audio or recognition updates") }
            XCTFail("Canceled startup must fail before touching audio hardware")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await fulfillment(of: [entered], timeout: 1)
    }
    func testCancellationIsImmediatelyVisibleAcrossThreadsAndSessionScoped() async {
        let old = SpeechSessionToken(), current = SpeechSessionToken()
        XCTAssertTrue(old.isActive)
        await Task.detached { old.cancel() }.value
        XCTAssertFalse(old.isActive)
        XCTAssertThrowsError(try old.checkActive())
        XCTAssertTrue(current.isActive)
        XCTAssertNoThrow(try current.checkActive())
    }
}
