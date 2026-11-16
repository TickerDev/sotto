import XCTest
@testable import SottoIntegrations
import SottoTools

final class AppleScriptExecutorTests: XCTestCase, @unchecked Sendable {
    func testHelperReturnsRealScriptOutputWithoutBlockingUI() async throws {
        let result = try await AppleScriptExecutor().execute("return \"Sotto helper test\"")
        XCTAssertEqual(result, "Sotto helper test")
    }
    func testHelperReportsScriptErrors() async throws {
        do { _ = try await AppleScriptExecutor().execute("error \"Expected test failure\" number 42"); XCTFail("Expected script failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Expected test failure")) }
    }
    func testHelperTimeoutIsEnforced() async throws {
        do { _ = try await AppleScriptExecutor().execute("delay 10\nreturn \"too late\"", timeout: 0.05); XCTFail("Helper did not time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
    }
    @MainActor func testRunningHelperCanBeCancelledFromMainActor() async throws {
        let started = expectation(description: "Helper launched")
        let child = Task {
            try await AppleScriptExecutor().execute("delay 10\nreturn \"too late\"", didStart: { started.fulfill() })
        }
        await fulfillment(of: [started], timeout: 5)
        MainActor.assertIsolated() // Reaching here while the script waits proves UI executor availability.
        child.cancel()
        do { _ = try await child.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
    }
    func testHelperRejectsOversizedOutput() async throws {
        do { _ = try await AppleScriptExecutor().execute("return \"" + String(repeating: "x", count: 70_000) + "\""); XCTFail("Expected output bound") }
        catch { XCTAssertTrue(error.localizedDescription.contains("too much data")) }
    }
    func testPlaybackVerificationDoesNotClaimUnconfirmedSuccess() throws {
        XCTAssertThrowsError(try SpotifyAction.pause.result("playing\tTest track"))
        XCTAssertThrowsError(try SpotifyAction.play.result("paused\tTest track"))
        XCTAssertThrowsError(try SpotifyAction.current.result("invalid"))
        XCTAssertEqual(try SpotifyAction.pause.result("paused\tTest track").summary, "Paused · Test track")
        XCTAssertNotNil(SpotifyAction(rawValue: "pause")); XCTAssertNil(SpotifyAction(rawValue: "pause; arbitrary code"))
    }
}
