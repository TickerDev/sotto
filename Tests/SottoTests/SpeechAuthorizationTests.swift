import XCTest
import Speech
@testable import SottoAudio

final class SpeechAuthorizationTests: XCTestCase, @unchecked Sendable {
    @MainActor func testBackgroundAuthorizationReturnsSafelyToMainActor() async {
        let status = await SpeechAuthorization.request { reply in
            DispatchQueue.global(qos: .userInitiated).async {
                XCTAssertFalse(Thread.isMainThread)
                reply(.authorized)
            }
        }
        MainActor.assertIsolated()
        XCTAssertEqual(status, .authorized)
    }

    @MainActor func testBackgroundDenialAndRestrictionArePreserved() async {
        for expected in [SFSpeechRecognizerAuthorizationStatus.denied, .restricted] {
            let status = await SpeechAuthorization.request { reply in
                DispatchQueue.global().async { reply(expected) }
            }
            MainActor.assertIsolated()
            XCTAssertEqual(status, expected)
        }
    }
}
