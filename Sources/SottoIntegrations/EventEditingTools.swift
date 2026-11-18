import Foundation
import EventKit
import SottoTools

struct CompleteReminderTool: Tool {
    let descriptor = ToolDescriptor(id: "reminders.complete", description: "Complete a reminder using its exact identifier and title; requires approval.", properties: ["id": textProperty("Reminder identifier"), "title": textProperty("Exact current title")], required: ["id", "title"], risk: .consequential, capabilities: [.reminders], permissions: ["Reminders full access"])
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw ToolError.denied("Allow Reminders access") }
        let store = EKEventStore()
        guard let item = store.calendarItem(withIdentifier: arguments.object?["id"]?.string ?? "") as? EKReminder,
              item.title == arguments.object?["title"]?.string else { throw ToolError.invalid("Reminder identity changed. List reminders again.") }
        guard item.calendar.allowsContentModifications else { throw ToolError.denied("This reminders list is read-only") }
        if item.isCompleted { return ToolResult("This reminder is already complete") }
        item.isCompleted = true
        try store.save(item, commit: true)
        guard let saved = store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKReminder, saved.isCompleted else { return ToolResult("Reminder saved, but completion could not be verified.", state: .partiallyCompleted) }
        return ToolResult("Completed “\(item.title ?? "reminder")”")
    }
}
struct UpdateCalendarTool: Tool {
    let descriptor = ToolDescriptor(id: "calendar.update", description: "Update a single non-recurring calendar event after approval. Requires exact identity and current title; refuses events with attendees.", properties: [
        "id": textProperty("Exact event identifier"), "current_title": textProperty("Existing title"),
        "title": textProperty("New title"), "start": textProperty("ISO8601 start with time zone"), "end": textProperty("ISO8601 end with time zone")
    ], required: ["id", "current_title", "title", "start", "end"], risk: .consequential, capabilities: [.calendar], permissions: ["Calendar full access"])
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        let f = ISO8601DateFormatter()
        guard let start = f.date(from: arguments.object?["start"]?.string ?? ""), let end = f.date(from: arguments.object?["end"]?.string ?? ""), end > start, end.timeIntervalSince(start) <= 31 * 86400,
              let title = arguments.object?["title"]?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.invalid("Provide a title and valid start/end dates with time zones") }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw ToolError.denied("Allow Calendar access") }
        let store = EKEventStore()
        guard let event = store.event(withIdentifier: arguments.object?["id"]?.string ?? ""),
              event.title == arguments.object?["current_title"]?.string else { throw ToolError.invalid("Event identity changed. List calendar events again.") }
        guard event.calendar.allowsContentModifications, !event.hasRecurrenceRules, event.attendees?.isEmpty != false else { throw ToolError.denied("Only writable, non-recurring events without attendees can be updated") }
        let id = event.eventIdentifier ?? ""
        event.title = title; event.startDate = start; event.endDate = end
        try store.save(event, span: .thisEvent, commit: true)
        guard let saved = store.event(withIdentifier: id), saved.title == title,
              abs(saved.startDate.timeIntervalSince(start)) < 1, abs(saved.endDate.timeIntervalSince(end)) < 1 else { return ToolResult("Event saved, but changes could not be verified. Check Calendar before retrying.", state: .partiallyCompleted) }
        return ToolResult("Updated “\(title)”", data: .string(id))
    }
}
