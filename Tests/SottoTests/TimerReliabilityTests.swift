import XCTest
import UserNotifications
import SottoTools
import SottoAgent
import SottoProviders
@testable import SottoIntegrations

private final class TimerTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}
private actor TimerTestPause {
    let began: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ began: XCTestExpectation) { self.began = began }
    func wait() async { began.fulfill(); await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private actor TimerNotificationFixture: TimerNotifications {
    private(set) var schedules: [SottoTimer] = []
    private(set) var permissionRequests: [Bool] = []
    private var requests: [String: Date] = [:]
    private var permissionValue: TimerAlertPermission = .alerts
    private var scheduleFailure = false
    private var removalWorks = true
    private var wrongDate = false
    var permissionPause: TimerTestPause?
    var schedulePause: TimerTestPause?
    func configure(permission: TimerAlertPermission = .alerts, fails: Bool = false, removalWorks: Bool = true, wrongDate: Bool = false,
                   permissionPause: TimerTestPause? = nil, schedulePause: TimerTestPause? = nil) {
        self.permissionValue = permission; self.scheduleFailure = fails; self.removalWorks = removalWorks; self.wrongDate = wrongDate
        self.permissionPause = permissionPause; self.schedulePause = schedulePause
    }
    func clearRequests() { requests = [:] }
    func permission(request: Bool) async throws -> TimerAlertPermission {
        permissionRequests.append(request)
        if let permissionPause { await permissionPause.wait() }
        return permissionValue
    }
    func pending() -> [PendingTimerAlert] { requests.map { .init(id: $0.key, date: $0.value) } }
    func schedule(_ timer: SottoTimer, remaining: TimeInterval) async throws {
        schedules.append(timer)
        if let schedulePause { await schedulePause.wait() }
        if scheduleFailure { throw ToolError.unavailable("Controlled scheduling failure") }
        requests[timer.id] = timer.deadline.addingTimeInterval(wrongDate ? 100 : 0)
    }
    func remove(_ id: String) -> Bool {
        guard removalWorks else { return false }
        requests.removeValue(forKey: id); return true
    }
}
final class TimerReliabilityTests: XCTestCase, @unchecked Sendable {
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SottoTimers-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("timers.json")
    }
    private func engine(_ file: URL, _ notifications: TimerNotificationFixture, _ clock: TimerTestClock) -> TimerEngine {
        TimerEngine(file: file, notifications: notifications, now: { clock.now() })
    }
    func testRelaunchRepairsMissingAlertsWithoutResettingDeadlineOrReplayingElapsedTimer() async throws {
        let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
        let original = engine(file, alerts, clock)
        let result = try await original.start(seconds: 600, name: "Water plants")
        XCTAssertEqual(result.state, .success)
        let savedRecord = try await original.list().first
        let saved = try XCTUnwrap(savedRecord)
        XCTAssertEqual(saved.deadline, clock.now().addingTimeInterval(600))
        clock.advance(60)
        let restored = engine(file, alerts, clock)
        try await restored.reconcile()
        var count = await alerts.schedules.count; XCTAssertEqual(count, 1)
        await alerts.clearRequests()
        try await restored.reconcile()
        let repaired = await alerts.schedules
        XCTAssertEqual(repaired.count, 2); XCTAssertEqual(repaired.last?.deadline, saved.deadline); XCTAssertEqual(repaired.last?.id, saved.id)
        clock.advance(600)
        let listing = try await restored.listing()
        XCTAssertEqual(listing.data.object?["active_count"], .number(0))
        XCTAssertTrue(listing.summary.contains("deadlines passed"))
        count = await alerts.schedules.count; XCTAssertEqual(count, 2)
        XCTAssertEqual(TimerEngine.data(saved, at: clock.now()).object?["delivery_verified"], .bool(false))
        let permissions = await alerts.permissionRequests
        XCTAssertEqual(permissions.filter { $0 }.count, 1, "Maintenance never prompts")
    }
    func testDeniedQuietAndSchedulingFailureKeepHonestPersistedTimers() async throws {
        for permission in [TimerAlertPermission.denied, .quiet, .notRequested] {
            let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
            await alerts.configure(permission: permission)
            let engine = engine(file, alerts, clock)
            let result = try await engine.start(seconds: 60, name: "")
            XCTAssertEqual(result.state, .partiallyCompleted)
            let saved = try await engine.list()
            XCTAssertEqual(saved.count, 1); XCTAssertEqual(saved.first?.name, "Timer")
            let restored = self.engine(file, alerts, clock)
            let restoredCount = try await restored.list().count
            XCTAssertEqual(restoredCount, 1)
        }
        let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
        await alerts.configure(fails: true)
        let engine = engine(file, alerts, clock)
        let result = try await engine.start(seconds: 60, name: "Test")
        XCTAssertEqual(result.state, .partiallyCompleted)
        let firstRecord = try await engine.list().first
        let first = try XCTUnwrap(firstRecord)
        XCTAssertEqual(first.delivery, .failed)
        await alerts.configure()
        try await engine.reconcile()
        let recovered = try await engine.list()
        XCTAssertEqual(recovered.first?.id, first.id); XCTAssertEqual(recovered.first?.delivery, .scheduled)
    }
    func testIncorrectNotificationDeadlineDoesNotCountAsVerifiedScheduling() async throws {
        let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
        await alerts.configure(wrongDate: true)
        let engine = engine(file, alerts, clock)
        let result = try await engine.start(seconds: 60, name: "Readback")
        XCTAssertEqual(result.state, .partiallyCompleted)
        XCTAssertEqual(result.data.object?["notification_state"], .string("failed"))
    }
    func testCancellationDuringSchedulingRemovesLateAlertAndCannotResurrectOnReload() async throws {
        let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
        let began = expectation(description: "Native adapter accepted scheduling")
        let pause = TimerTestPause(began)
        await alerts.configure(schedulePause: pause)
        let engine = engine(file, alerts, clock)
        let task = Task { try await engine.start(seconds: 600, name: "Race") }
        await fulfillment(of: [began], timeout: 2)
        let inFlightRecord = try await engine.list().first
        let saved = try XCTUnwrap(inFlightRecord)
        let cancellation = try await engine.cancel(id: saved.id)
        XCTAssertEqual(cancellation.state, .partiallyCompleted)
        await pause.release()
        let result = try await task.value
        XCTAssertEqual(result.state, .cancelled)
        let timerRemoved = try await engine.list().isEmpty
        XCTAssertTrue(timerRemoved)
        let alertRemoved = await alerts.pending().isEmpty
        XCTAssertTrue(alertRemoved)
        let restored = self.engine(file, alerts, clock)
        try await restored.reconcile()
        let restoredEmpty = try await restored.list().isEmpty
        XCTAssertTrue(restoredEmpty)
        let count = await alerts.schedules.count; XCTAssertEqual(count, 1)
    }
    func testUnverifiedRemovalKeepsDurableCancellationTombstone() async throws {
        let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
        let engine = engine(file, alerts, clock)
        _ = try await engine.start(seconds: 60, name: "Cancel")
        let initialRecord = try await engine.list().first
        let saved = try XCTUnwrap(initialRecord)
        await alerts.configure(removalWorks: false)
        let result = try await engine.cancel(id: saved.id)
        XCTAssertEqual(result.state, .partiallyCompleted)
        let restored = self.engine(file, alerts, clock)
        let listing = try await restored.listing()
        XCTAssertEqual(listing.data.object?["active_count"], .number(0))
        XCTAssertTrue(listing.summary.contains("cancellations"))
        let count = await alerts.schedules.count; XCTAssertEqual(count, 1)
        await alerts.configure()
        try await restored.reconcile()
        let tombstoneRemoved = try await restored.list().isEmpty
        XCTAssertTrue(tombstoneRemoved)
    }
    func testPermissionDelayUsesOriginalDeadlineAndCancellationCleansUp() async throws {
        for cancelled in [false, true] {
            let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
            let began = expectation(description: "Permission awaited")
            let pause = TimerTestPause(began)
            await alerts.configure(permissionPause: pause)
            let engine = engine(file, alerts, clock)
            let task = Task { try await engine.start(seconds: 10, name: "Waiting") }
            await fulfillment(of: [began], timeout: 2)
            if cancelled { task.cancel() } else { clock.advance(20) }
            await pause.release()
            if cancelled {
                do { _ = try await task.value; XCTFail() } catch is CancellationError {}
                let cancelledEmpty = try await engine.list().isEmpty
                XCTAssertTrue(cancelledEmpty)
            } else {
                let result = try await task.value
                XCTAssertEqual(result.state, .partiallyCompleted)
                XCTAssertEqual(result.data.object?["notification_state"], .string("elapsedUnverified"))
            }
            let count = await alerts.schedules.count; XCTAssertEqual(count, 0)
        }
    }
    func testCorruptOversizedDuplicateOrUnwritableStorageCannotDispatchAndPreservesBytes() async throws {
        let clock = TimerTestClock()
        let duplicate = SottoTimer(id: "duplicate", name: "Fixture", deadline: clock.now().addingTimeInterval(60))
        for bytes in [Data("corrupt".utf8), Data(repeating: 0, count: 1_000_001), try JSONEncoder().encode([duplicate, duplicate])] {
            let file = try file(), alerts = TimerNotificationFixture()
            try bytes.write(to: file)
            let engine = engine(file, alerts, clock)
            do { _ = try await engine.start(seconds: 60, name: "No dispatch"); XCTFail() } catch {}
            do { _ = try await engine.list(); XCTFail() } catch {}
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            let requests = await alerts.permissionRequests
            XCTAssertTrue(requests.isEmpty)
        }
        let file = try file(), alerts = TimerNotificationFixture()
        try Data().write(to: file)
        let invalid = engine(file.appendingPathComponent("child.json"), alerts, clock)
        do { _ = try await invalid.start(seconds: 60, name: "No storage"); XCTFail() } catch {}
        let requests = await alerts.permissionRequests
        XCTAssertTrue(requests.isEmpty)
    }
    func testConcurrentStartsRespectReservedActiveLimitAndLegacyMigration() async throws {
        let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
        let legacy = (0..<49).map { SottoTimer(id: "legacy-\($0)", name: "Old timer", deadline: clock.now().addingTimeInterval(600)) }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [[String: Any]]
        for index in json.indices { json[index].removeValue(forKey: "delivery") }
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let engine = engine(file, alerts, clock)
        let legacyDelivery = try await engine.list().first?.delivery
        XCTAssertEqual(legacyDelivery, .needsScheduling)
        let began = expectation(description: "Fiftieth slot reserved")
        let pause = TimerTestPause(began)
        await alerts.configure(permissionPause: pause)
        let task = Task { try await engine.start(seconds: 600, name: "Fiftieth") }
        await fulfillment(of: [began], timeout: 2)
        do { _ = try await engine.start(seconds: 600, name: "Too many"); XCTFail() } catch {}
        await pause.release()
        _ = try await task.value
        let activeCount = try await engine.list().count
        XCTAssertEqual(activeCount, 50)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testNativeCalendarRequestUsesAbsoluteUTCDeadlineAndNoRepeatingTrigger() throws {
        let deadline = Date().addingTimeInterval(600.25)
        let timer = SottoTimer(id: "sotto.timer.fixture", name: "Native fixture", deadline: deadline)
        let request = NativeTimerNotifications.request(timer)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        let next = try XCTUnwrap(trigger.nextTriggerDate())
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(next.timeIntervalSince1970, deadline.timeIntervalSince1970.rounded(.up), accuracy: 0.01)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(request.content.title, timer.name)
    }
    func testOptionalNameAndNativeListingDoNotRenderTimersAsFileResults() async throws {
        let file = try file(), alerts = TimerNotificationFixture(), clock = TimerTestClock()
        let engine = engine(file, alerts, clock)
        _ = try await TimerTool(action: "start", engine: engine).execute(arguments: .object(["seconds": .number(600)]))
        let result = try await TimerTool(action: "list", engine: engine).execute(arguments: .object([:]))
        XCTAssertEqual(result.data.object?["active_count"], .number(1))
        let provider = try XCTUnwrap(NativeCommandProvider(command: "Show my active timers"))
        var text = ""
        for try await event in provider.stream(input: [.object(["type": .string("function_call_output"), "output": .string(result.encoded)])], tools: [], instructions: "") {
            if case .text(let part) = event { text += part }
        }
        XCTAssertTrue(text.contains("Timer: 10m")); XCTAssertFalse(text.contains("PDF"))
    }
}
