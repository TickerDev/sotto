import XCTest
import EventKit
import SottoAgent
import SottoTools
import SottoSecurity
@testable import SottoIntegrations
@testable import SottoUI

private actor AgendaProbe: AgendaSource {
    let items: [AgendaEvent]
    var reads = 0
    init(_ items: [AgendaEvent] = []) { self.items = items }
    func events(in interval: DateInterval) -> [AgendaEvent] { reads += 1; return items }
}
private actor AgendaConnection {
    var pending: CheckedContinuation<Void, Never>?
    func wait(_ started: @Sendable () -> Void) async {
        await withCheckedContinuation { pending = $0; started() }
    }
    func finish() { pending?.resume(); pending = nil }
}

final class CalendarTests: XCTestCase, @unchecked Sendable {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private var range: JSONValue { .object(["start": .string("2026-11-16T00:00:00-06:00"), "end": .string("2026-11-17T00:00:00-06:00")]) }

    func testNativeAgendaUsesLocalDayBoundariesIncludingDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let provider = try XCTUnwrap(NativeCommandProvider(command: "What’s on my calendar tomorrow?", now: date("2026-03-07T12:00:00-06:00"), calendar: calendar))
        XCTAssertEqual(provider.tool, "list_calendar_events")
        XCTAssertEqual(provider.arguments.object?["start"], .string("2026-03-08T06:00:00Z"))
        XCTAssertEqual(provider.arguments.object?["end"], .string("2026-03-09T05:00:00Z"))
        for text in ["don't show my calendar tomorrow", "what's on my calendar someday", "show my calendar today and delete events", "send my calendar today"] {
            XCTAssertNil(NativeCommandProvider(command: text), text)
        }
    }

    func testInvalidRangesFailBeforeReadingCalendar() async throws {
        let source = AgendaProbe(), tool = ListCalendarEventsTool(source: AgendaProbe())
        let checked = ListCalendarEventsTool(source: source)
        for args: JSONValue in [.object([:]), .object(["start": .string("invalid"), "end": .string("invalid")]),
            .object(["start": .string("2026-11-17T00:00:00Z"), "end": .string("2026-11-16T00:00:00Z")]),
            .object(["start": .string("2026-01-01T00:00:00Z"), "end": .string("2027-01-01T00:00:00Z")])] {
            do { _ = try await checked.execute(arguments: args); XCTFail("Accepted invalid range") } catch is ToolError {}
        }
        let reads = await source.reads
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(tool.descriptor.risk, .read)
        XCTAssertEqual(tool.descriptor.capabilities, [.calendar])
    }

    func testAgendaSortsOverlappingEventsAndIncludesAllDayWithoutPrivateNotes() async throws {
        let start = date("2026-11-16T08:00:00-06:00"), end = date("2026-11-16T09:00:00-06:00")
        let source = AgendaProbe([
            AgendaEvent(title: "Later", start: end, end: end.addingTimeInterval(3600), allDay: false),
            AgendaEvent(title: "First", start: start, end: end, allDay: false),
            AgendaEvent(title: "Day off", start: date("2026-11-16T00:00:00-06:00"), end: date("2026-11-17T00:00:00-06:00"), allDay: true),
            AgendaEvent(title: "Outside", start: date("2026-11-17T00:00:00-06:00"), end: date("2026-11-18T00:00:00-06:00"), allDay: false)
        ])
        let result = try await ListCalendarEventsTool(source: source).execute(arguments: range)
        XCTAssertEqual(result.data.object?["total"], .number(3))
        XCTAssertTrue(result.data.object?["agenda"]?.string?.contains("All day") == true)
        XCTAssertFalse(result.summary.contains("Day off"), "Activity summaries need not retain event titles")
        guard case .array(let events) = result.data.object?["events"] else { return XCTFail("Missing event data") }
        XCTAssertEqual(events.compactMap { $0.object?["title"]?.string }, ["Day off", "First", "Later"])
        XCTAssertEqual(Set(events[0].object!.keys), Set(["title", "start", "end", "all_day", "id"]))
    }

    func testEmptyAndCappedAgendasAreHonest() async throws {
        let empty = try await ListCalendarEventsTool(source: AgendaProbe()).execute(arguments: range)
        XCTAssertTrue(empty.summary.hasPrefix("No events"))
        let start = date("2026-11-16T08:00:00-06:00")
        let items = (0..<40).map { AgendaEvent(title: "Event \($0)", start: start, end: start.addingTimeInterval(600), allDay: false) }
        let result = try await ListCalendarEventsTool(source: AgendaProbe(items)).execute(arguments: range)
        XCTAssertEqual(result.data.object?["total"], .number(40))
        XCTAssertEqual(result.data.object?["truncated"], .bool(true))
        guard case .array(let events) = result.data.object?["events"] else { return XCTFail("Missing events") }
        XCTAssertEqual(events.count, 30)
        XCTAssertTrue(result.data.object?["agenda"]?.string?.contains("first 30") == true)
    }

    @MainActor func testCalendarPermissionDistinguishesWriteOnlyDeniedAndFullAccess() {
        XCTAssertEqual(PermissionCenter.calendarState(.fullAccess), .allowed)
        XCTAssertEqual(PermissionCenter.calendarState(.writeOnly), .notRequested)
        XCTAssertEqual(PermissionCenter.calendarState(.notDetermined), .notRequested)
        XCTAssertEqual(PermissionCenter.calendarState(.denied), .denied)
        XCTAssertEqual(PermissionCenter.calendarState(.restricted), .restricted)
        XCTAssertEqual(IntegrationAccessRequest(kind: .calendar).kind, .calendar)
        XCTAssertEqual(IntegrationAccessRequest().kind, .reminders)
    }

    func testBlockedPermissionRequestIsNotReportedAsUserCancellation() {
        XCTAssertEqual(PermissionRequestOutcome.afterRequest(state: .notRequested), .unavailable)
        XCTAssertEqual(PermissionRequestOutcome.afterRequest(state: .allowed), .allowed)
        XCTAssertEqual(PermissionRequestOutcome.afterRequest(state: .denied), .notGranted)
        XCTAssertEqual(PermissionRequestOutcome.afterRequest(state: .restricted), .notGranted)
        XCTAssertEqual(PermissionRequestOutcome.afterRequest(state: .notRequested, returnedError: true), .unavailable)
        XCTAssertFalse(IntegrationAccessError.unavailable("Calendar").localizedDescription.contains("cancelled"))
        XCTAssertFalse(IntegrationAccessError.notGranted("Calendar").localizedDescription.contains("cancelled"))
        XCTAssertTrue(IntegrationAccessError.settingsRequired("Calendar").localizedDescription.contains("System Settings"))
    }

    func testAgendaWaitsForAccessThenExecutesOnceAndReturnsReadableNativeReply() async throws {
        let source = AgendaProbe(), connection = AgendaConnection()
        let waiting = expectation(description: "Calendar connection pending")
        let runtime = AgentRuntime(registry: ToolRegistry([ListCalendarEventsTool(source: source)]), gate: AuthorizationGate())
        let provider = try XCTUnwrap(NativeCommandProvider(command: "What's on my calendar today?"))
        let task = Task {
            try await runtime.run("What's on my calendar today?", provider: provider, prepare: { descriptor in
                XCTAssertEqual(descriptor.capabilities, [.calendar])
                await connection.wait { waiting.fulfill() }
            }) { _ in }
        }
        await fulfillment(of: [waiting], timeout: 2)
        let before = await source.reads
        XCTAssertEqual(before, 0)
        await connection.finish()
        let context = try await task.value
        let after = await source.reads
        XCTAssertEqual(after, 1)
        XCTAssertTrue(context.last?.object?["content"]?.string?.hasPrefix("No events") == true)
    }

    func testCancelledCalendarConnectionCannotReadOrResume() async throws {
        let source = AgendaProbe(), connection = AgendaConnection()
        let waiting = expectation(description: "Calendar connection pending")
        let runtime = AgentRuntime(registry: ToolRegistry([ListCalendarEventsTool(source: source)]), gate: AuthorizationGate())
        let task = Task {
            try await runtime.run("Show my calendar today", provider: XCTUnwrap(NativeCommandProvider(command: "Show my calendar today")), prepare: { _ in
                await connection.wait { waiting.fulfill() }
            }) { _ in }
        }
        await fulfillment(of: [waiting], timeout: 2)
        task.cancel(); await connection.finish()
        do { _ = try await task.value; XCTFail("Cancelled agenda resumed") } catch is CancellationError {}
        let reads = await source.reads
        XCTAssertEqual(reads, 0)
    }
}
