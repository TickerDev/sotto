import Foundation
import EventKit
import SottoTools

struct AgendaEvent: Sendable, Equatable {
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    var identifier: String = ""
}

protocol AgendaSource: Sendable {
    func events(in interval: DateInterval) async throws -> [AgendaEvent]
}

/// EventKit objects stay on this executor; only immutable snapshots leave it.
/// No writes or permission prompts are exposed by this adapter.
private actor EventKitAgendaSource: AgendaSource {
    private var store: EKEventStore?
    func events(in interval: DateInterval) async throws -> [AgendaEvent] {
        try Task.checkCancellation()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw ToolError.denied("Allow Calendar access in Sotto’s Permissions settings to read your agenda.")
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        let events = store.events(matching: predicate).filter { $0.status != .canceled }.map {
            AgendaEvent(title: String(($0.title ?? "Untitled event").prefix(256)), start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, identifier: $0.eventIdentifier ?? "")
        }
        try Task.checkCancellation()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw ToolError.denied("Calendar access changed. Your agenda was not returned.")
        }
        return events
    }
}

struct ListCalendarEventsTool: Tool {
    let descriptor = ToolDescriptor(id: "list_calendar_events", description: "Read calendar events in a date range of up to 31 days", properties: [
        "start": textProperty("Inclusive start: ISO8601 date and time with timezone"),
        "end": textProperty("Exclusive end: ISO8601 date and time with timezone")
    ], required: ["start", "end"], risk: .read, capabilities: [.calendar])
    private let source: any AgendaSource
    init(source: any AgendaSource = EventKitAgendaSource()) { self.source = source }

    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let formatter = ISO8601DateFormatter()
        guard let startText = arguments.object?["start"]?.string, let start = formatter.date(from: startText),
              let endText = arguments.object?["end"]?.string, let end = formatter.date(from: endText),
              end > start, end.timeIntervalSince(start) <= 31 * 86_400 + 3_600 else {
            throw ToolError.invalid("Choose a calendar date range of up to 31 days, including a timezone.")
        }
        try Task.checkCancellation()
        let interval = DateInterval(start: start, end: end)
        let fetched = try await source.events(in: interval)
        try Task.checkCancellation()
        let events = fetched.filter { $0.start < end && $0.end > start }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let visible = Array(events.prefix(30))
        let heading = start.formatted(date: .abbreviated, time: .omitted)
        let summary = events.isEmpty ? "No events from \(heading) in the requested range." : "Found \(events.count) calendar \(events.count == 1 ? "event" : "events") from \(heading)."
        let lines = visible.map { event in
            let date = event.start.formatted(date: .abbreviated, time: .omitted)
            let time = event.allDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
            return "\(date) · \(time)\n\(event.title)"
        }
        var agenda = lines.isEmpty ? summary : lines.joined(separator: "\n\n")
        if events.count > visible.count { agenda += "\n\nShowing the first 30 events. Ask for a shorter date range to see more." }
        return ToolResult(summary, data: .object([
            "agenda": .string(agenda), "total": .number(Double(events.count)),
            "truncated": .bool(events.count > visible.count),
            "events": .array(visible.map { .object([
                "id": .string($0.identifier), "title": .string($0.title), "start": .string(formatter.string(from: $0.start)),
                "end": .string(formatter.string(from: $0.end)), "all_day": .bool($0.allDay)
            ]) })
        ]))
    }
}
