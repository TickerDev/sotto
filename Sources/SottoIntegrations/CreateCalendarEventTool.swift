import EventKit
import Foundation
import SottoTools

struct NewCalendarEvent: Hashable, Sendable {
    let title: String
    let start: Date
    let end: Date
}
struct CreatedCalendarEvent: Sendable {
    let identifier: String
    let event: NewCalendarEvent
}
protocol CalendarEventWriter: Sendable {
    func create(_ event: NewCalendarEvent) async throws -> CreatedCalendarEvent
}

struct CalendarWriteAttempts {
    private struct Attempt { let date: Date; var identifier: String? }
    private var attempts: [NewCalendarEvent: Attempt] = [:]
    mutating func reserve(_ event: NewCalendarEvent, now: Date = Date()) throws -> String? {
        attempts = attempts.filter { now.timeIntervalSince($0.value.date) < 900 }
        if let attempt = attempts[event] {
            guard let id = attempt.identifier else { throw ToolError.unavailable("This event was already attempted. Check Calendar before asking again; Sotto will not create a duplicate.") }
            return id
        }
        guard attempts.count < 64 else { throw ToolError.unavailable("Too many recent event requests. Check Calendar and try again later.") }
        attempts[event] = Attempt(date: now, identifier: nil)
        return nil
    }
    mutating func confirmed(_ event: NewCalendarEvent, identifier: String) { attempts[event]?.identifier = identifier }
}

/// EventKit objects never leave this actor. Repeated model proposals within the
/// same app session cannot create duplicate events after a successful/uncertain save.
private actor EventKitEventWriter: CalendarEventWriter {
    private let store = EKEventStore()
    private var attempts = CalendarWriteAttempts()
    func create(_ event: NewCalendarEvent) throws -> CreatedCalendarEvent {
        try Task.checkCancellation()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw ToolError.denied("Allow Calendar access to add and verify your event.")
        }
        guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
            throw ToolError.unavailable("Choose a writable default calendar in Calendar settings first.")
        }
        try Task.checkCancellation()
        if let id = try attempts.reserve(event) {
            guard let saved = store.event(withIdentifier: id), matches(saved, event) else {
                throw ToolError.unavailable("This event was already attempted. Check Calendar before asking again; Sotto will not create a duplicate.")
            }
            return CreatedCalendarEvent(identifier: id, event: event)
        }
        let item = EKEvent(eventStore: store)
        item.calendar = calendar; item.title = event.title; item.startDate = event.start; item.endDate = event.end
        item.isAllDay = false
        try Task.checkCancellation()
        do { try store.save(item, span: .thisEvent, commit: true) }
        catch { throw ToolError.unavailable("Calendar could not confirm the save. Check Calendar before trying again; the event may have been saved.") }
        guard let id = item.eventIdentifier, !id.isEmpty else {
            throw ToolError.unavailable("Calendar saved without a usable identifier. Check Calendar before trying again.")
        }
        attempts.confirmed(event, identifier: id)
        guard let saved = store.event(withIdentifier: id), matches(saved, event) else {
            throw ToolError.unavailable("The event save could not be verified. Check Calendar before trying again.")
        }
        // Once committed, return evidence even if cancellation arrived during
        // the synchronous save. The runtime records actual late side effects.
        return CreatedCalendarEvent(identifier: id, event: event)
    }
    private func matches(_ saved: EKEvent, _ event: NewCalendarEvent) -> Bool {
        saved.title == event.title && !saved.isAllDay && saved.attendees?.isEmpty != false &&
        abs(saved.startDate.timeIntervalSince(event.start)) < 1 && abs(saved.endDate.timeIntervalSince(event.end)) < 1
    }
}

struct CreateCalendarEventTool: Tool {
    let descriptor = ToolDescriptor(id: "create_calendar_event", description: "Create a single personal timed event in the default writable calendar, with verified save. The user's clear request authorizes creation. Requires explicit start and end including timezone; ask if time or duration is missing. No invitations, attendees, recurrence, edits or deletion.", properties: [
        "title": textProperty("Event title, 1–256 characters"),
        "start": textProperty("Start: ISO8601 date/time with timezone"),
        "end": textProperty("End: ISO8601 date/time with timezone; must be later than start")
    ], required: ["title", "start", "end"], risk: .reversible, capabilities: [.calendar])
    private let writer: any CalendarEventWriter
    private let now: @Sendable () -> Date
    init(writer: any CalendarEventWriter = EventKitEventWriter(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.writer = writer; self.now = now
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let title = (arguments.object?["title"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        guard !title.isEmpty, title.count <= 256,
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let start = formatter.date(from: arguments.object?["start"]?.string ?? ""),
              let end = formatter.date(from: arguments.object?["end"]?.string ?? ""),
              start >= now().addingTimeInterval(-60), end > start, end.timeIntervalSince(start) <= 7 * 86_400 else {
            throw ToolError.invalid("Provide a title and a future start/end time with timezone, lasting up to seven days. Ask for any missing date, time or duration.")
        }
        try Task.checkCancellation()
        let event = NewCalendarEvent(title: title, start: start, end: end)
        let saved = try await writer.create(event)
        guard !saved.identifier.isEmpty, saved.event == event else { throw ToolError.unavailable("Calendar did not confirm the requested event. Check Calendar before trying again.") }
        let endLabel = end.formatted(date: Calendar.current.isDate(start, inSameDayAs: end) ? .omitted : .abbreviated, time: .shortened)
        return ToolResult("Created “\(title)” · \(start.formatted(date: .abbreviated, time: .shortened))–\(endLabel)", data: .object([
            "identifier": .string(saved.identifier), "title": .string(title),
            "start": .string(formatter.string(from: start)), "end": .string(formatter.string(from: end))
        ]))
    }
}
