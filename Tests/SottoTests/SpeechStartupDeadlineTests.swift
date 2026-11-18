import XCTest
@testable import SottoAudio

private actor UncooperativeSpeechStartup {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(entered: @Sendable () -> Void) async {
        await withCheckedContinuation { continuation = $0; entered() }
    }
    func release() { continuation?.resume(); continuation = nil }
}
private final class StartupAbortProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func abort() { lock.withLock { count += 1 } }
    var calls: Int { lock.withLock { count } }
}

final class SpeechStartupDeadlineTests: XCTestCase, @unchecked Sendable {
    func testTimeoutReturnsBeforeUncooperativeFrameworkCallResumes() async {
        let blocked = UncooperativeSpeechStartup(), probe = StartupAbortProbe()
        let entered = expectation(description: "Framework call suspended")
        let returned = expectation(description: "Timeout returned without framework completion")
        let token = SpeechSessionToken()
        let task = Task {
            do {
                try await SpeechStartupDeadline.run(timeout: .milliseconds(80), operation: {
                    await blocked.wait { entered.fulfill() }
                    try token.checkActive()
                }, onAbort: { token.cancel(); probe.abort() })
                XCTFail("Timeout must fail")
            } catch {
                XCTAssertEqual(error.localizedDescription, "On-device speech did not become ready. Try again.")
                XCTAssertFalse(token.isActive)
            }
            returned.fulfill()
        }
        await fulfillment(of: [entered, returned], timeout: 2)
        XCTAssertEqual(probe.calls, 1)
        await blocked.release()
        await task.value
    }

    func testCancellationReturnsWithoutWaitingAndDoesNotCancelNextSession() async {
        let blocked = UncooperativeSpeechStartup(), probe = StartupAbortProbe()
        let entered = expectation(description: "Framework call suspended"), returned = expectation(description: "Cancellation returned")
        let old = SpeechSessionToken(), current = SpeechSessionToken()
        let task = Task {
            do {
                try await SpeechStartupDeadline.run(timeout: .seconds(30), operation: {
                    await blocked.wait { entered.fulfill() }
                    try old.checkActive()
                }, onAbort: { old.cancel(); probe.abort() })
                XCTFail("Canceled startup must fail")
            } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
            returned.fulfill()
        }
        await fulfillment(of: [entered], timeout: 1)
        task.cancel()
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertFalse(old.isActive)
        XCTAssertTrue(current.isActive)
        XCTAssertEqual(probe.calls, 1)
        await blocked.release()
        await task.value
    }

    func testSuccessfulStartupCancelsDeadlineWithoutAbortingSession() async throws {
        let probe = StartupAbortProbe()
        try await SpeechStartupDeadline.run(timeout: .milliseconds(30), operation: {}, onAbort: { probe.abort() })
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(probe.calls, 0)
    }

    func testAlreadyCanceledCallerNeverBeginsFrameworkWork() async {
        let probe = StartupAbortProbe()
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await SpeechStartupDeadline.run(timeout: .seconds(1), operation: {
                    XCTFail("Already canceled startup must not begin framework work")
                }, onAbort: { probe.abort() })
                XCTFail("Cancellation must propagate")
            } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        }.value
        XCTAssertEqual(probe.calls, 1)
    }

    func testFrameworkFailureIsPreservedAndAbortsExactlyOnce() async {
        let probe = StartupAbortProbe()
        do {
            try await SpeechStartupDeadline.run(timeout: .seconds(1), operation: {
                throw SpeechError.recognitionUnavailable
            }, onAbort: { probe.abort() })
            XCTFail("Framework failure must propagate")
        } catch SpeechError.recognitionUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(probe.calls, 1)
    }
}
