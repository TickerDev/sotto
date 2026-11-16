import XCTest
import SottoAudioBridgeFixtures

final class AudioExceptionTests: XCTestCase {
    func testTapUses48kHardwareInsteadOfStale16kClientFormat() {
        XCTAssertTrue(SottoTestUsesCurrentHardwareFormat())
    }
    func testFormatRaceBecomesRecoverableErrorInsteadOfAbort() throws {
        let error = try XCTUnwrap(SottoTestTapException())
        XCTAssertEqual((error as NSError).domain, "org.sotto.mac.audio")
        XCTAssertTrue(error.localizedDescription.contains("microphone"))
        XCTAssertTrue(error.localizedDescription.contains("Voice settings"))
        // A failed install doesn't prevent a fresh session from installing a tap.
        XCTAssertTrue(SottoTestUsesCurrentHardwareFormat())
    }
    func testEnginePreparationAndCleanupExceptionsCannotTerminateProcess() {
        XCTAssertNotNil(SottoTestPrepareException())
        XCTAssertNotNil(SottoTestStopException())
    }
}
