import XCTest
import SottoAgent
import SottoSecurity
import SottoTools
@testable import SottoIntegrations

private actor CalendarWriteProbe: CalendarEventWriter {
    var saved: [NewCalendarEvent] = []
    let mismatch: Bool
    init(mismatch: Bool = false) { self.mismatch = mismatch }
    func create(_ event: NewCalendarEvent) -> CreatedCalendarEvent {
        saved.append(event)
        return CreatedCalendarEvent(identifier: mismatch ? "" : "verified-fixture-event", event: event)
    }
}
final class CalendarCreationTests: XCTestCase, @unchecked Sendable {
    private let now = ISO8601DateFormatter().date(from: "2026-11-15T12:00:00-06:00")!
    private var args: JSONValue { .object(["title": .string("Review my Notes"), "start": .string("2026-11-16T17:00:00-06:00"), "end": .string("2026-11-16T17:30:00-06:00")]) }
    func testNativeCreationPreservesTitleAndRequiresUnambiguousTimeAndDuration() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let provider = try XCTUnwrap(NativeCommandProvider(command: "Schedule Review my Notes tomorrow at 5 PM for 30 minutes", now: now, calendar: calendar))
        XCTAssertEqual(provider.tool, "create_calendar_event")
        XCTAssertEqual(provider.arguments.object?["title"], .string("Review my Notes"))
        XCTAssertEqual(provider.arguments.object?["start"], .string("2026-11-16T23:00:00Z"))
        XCTAssertEqual(provider.arguments.object?["end"], .string("2026-11-16T23:30:00Z"))
        for request in ["Schedule Review tomorrow at 5", "Schedule Review tomorrow at 5 PM", "Don't schedule Review tomorrow at 5 PM for 30 minutes", "Schedule Review tomorrow at 13 PM for 30 minutes", "Schedule Review tomorrow at 5 PM for 0 minutes", "Schedule Review tomorrow at 5 PM for 30 minutes and email Bob"] {
            XCTAssertNil(NativeCommandProvider(command: request, now: now, calendar: calendar), request)
        }
    }
    func testInvalidOrMissingParametersCannotWrite() async throws {
        let probe = CalendarWriteProbe(), date = now
        let tool = CreateCalendarEventTool(writer: probe, now: { date })
        var invalid: [JSONValue] = [.object([:])]
        for (key, value): (String, JSONValue) in [("title", .string(" ")), ("title", .string("Bad\nTitle")), ("title", .string(String(repeating: "x", count: 257))), ("start", .string("2026-11-16T17:00:00")), ("start", .string("2026-11-14T17:00:00Z")), ("end", .string("2026-11-16T16:00:00-06:00")), ("end", .string("2026-12-16T17:00:00Z")), ("attendees", .string("bob@example.com"))] {
            var object = args.object!; object[key] = value; invalid.append(.object(object))
        }
        for arguments in invalid {
            do { _ = try await tool.execute(arguments: arguments); XCTFail("Accepted invalid event") } catch is ToolError {}
        }
        let saved = await probe.saved
        XCTAssertTrue(saved.isEmpty)
    }
    func testConfirmedReceiptRequiredAndRequestedCreationHasNoSecondApproval() async throws {
        let date = now, probe = CalendarWriteProbe()
        let tool = CreateCalendarEventTool(writer: probe, now: { date })
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate())
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let request = "Schedule Review my Notes tomorrow at 5 PM for 30 minutes"
        let provider = try XCTUnwrap(NativeCommandProvider(command: request, now: now, calendar: calendar))
        _ = try await runtime.run(request, provider: provider) { event in
            if case .approval = event { XCTFail("Clear personal event creation should run directly") }
            if case .result(_, let result) = event { XCTAssertEqual(result.data.object?["identifier"], .string("verified-fixture-event")) }
        }
        let saved = await probe.saved
        XCTAssertEqual(saved.count, 1)
        let bad = CreateCalendarEventTool(writer: CalendarWriteProbe(mismatch: true), now: { date })
        do { _ = try await bad.execute(arguments: args); XCTFail("Unverified save reported success") } catch is ToolError {}
    }
    func testCancelledRequestNeverWrites() async throws {
        let date = now, probe = CalendarWriteProbe(), arguments = args
        let tool = CreateCalendarEventTool(writer: probe, now: { date })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await tool.execute(arguments: arguments)
        }
        do { _ = try await task.value; XCTFail("Canceled task succeeded") } catch is CancellationError {}
        let saved = await probe.saved
        XCTAssertTrue(saved.isEmpty)
    }
    func testUncertainOrConfirmedSaveCannotBeRepeatedWithinRetryWindow() throws {
        var attempts = CalendarWriteAttempts()
        let event = NewCalendarEvent(title: "Review", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200))
        XCTAssertNil(try attempts.reserve(event, now: now))
        XCTAssertThrowsError(try attempts.reserve(event, now: now.addingTimeInterval(2)))
        attempts.confirmed(event, identifier: "actual-id")
        XCTAssertEqual(try attempts.reserve(event, now: now.addingTimeInterval(3)), "actual-id")
        XCTAssertNil(try attempts.reserve(event, now: now.addingTimeInterval(901)))
    }
    func testNativeDatesRejectMissingAndRepeatedDaylightSavingTimes() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let formatter = ISO8601DateFormatter()
        for (date, time) in [("2026-03-07T12:00:00-06:00", "2:30 AM"), ("2026-10-31T12:00:00-05:00", "1:30 AM")] {
            XCTAssertNil(NativeCommandProvider(command: "Schedule Review tomorrow at \(time) for 30 minutes", now: formatter.date(from: date)!, calendar: calendar))
        }
    }
}
