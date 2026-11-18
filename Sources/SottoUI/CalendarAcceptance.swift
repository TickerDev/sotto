#if DEBUG
import Foundation
import EventKit
import SottoAgent
import SottoTools
import SottoSecurity
import SottoIntegrations

/// Explicit Debug-only account acceptance. No permission prompts or inference.
/// Cleanup can remove only the uniquely named event created by this run.
public enum CalendarAcceptance {
    public static func run() async throws -> String {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw ToolError.denied("Calendar acceptance needs existing full access. No permission was requested and no event was created.")
        }
        let title = "Sotto verification \(UUID().uuidString)"
        let command = "Schedule \(title) tomorrow at 5 PM for 5 minutes"
        guard let provider = NativeCommandProvider(command: command) else { throw ToolError.invalid("The native Calendar route was unavailable.") }
        let probe = CalendarAcceptanceEvidence()
        let registry = NativeTools.registry()
        let runtime = AgentRuntime(registry: registry, gate: AuthorizationGate())
        do {
            for _ in 0..<2 {
                _ = try await runtime.run(command, provider: provider) { await probe.accept($0) }
            }
            let results = await probe.results
            guard results.count == 2,
                  let first = results.first?.data.object,
                  let identifier = first["identifier"]?.string,
                  identifier == results.last?.data.object?["identifier"]?.string,
                  first["title"]?.string == title else {
                throw ToolError.unavailable("Repeated Calendar requests did not return matching verified evidence.")
            }
            let agenda = try await registry.tool("list_calendar_events").execute(arguments: .object([
                "start": first["start"] ?? .null, "end": first["end"] ?? .null
            ]))
            guard case .array(let events) = agenda.data.object?["events"],
                  events.filter({ $0.object?["title"]?.string == title && $0.object?["start"] == first["start"] && $0.object?["end"] == first["end"] }).count == 1 else {
                throw ToolError.unavailable("The actual agenda tool did not find exactly one matching test event.")
            }
            let removed = try await CalendarAcceptanceCleanup().verifyAndRemove(first, expectedTitle: title)
            guard removed else { throw ToolError.unavailable("Test event cleanup could not be verified.") }
            return "Real Calendar check passed.\n\nThe native request created a five-minute event, its identifier and title/times were verified, and the repeated request reused that same event. The production agenda tool found exactly one matching event in that five-minute window. The test event was then removed and its absence verified.\n\nNo invitations, AI requests or permission changes were made."
        } catch {
            // Only verified evidence produced by this run can enter cleanup.
            if let data = await probe.results.first?.data.object {
                _ = try? await CalendarAcceptanceCleanup().verifyAndRemove(data, expectedTitle: title)
            }
            throw error
        }
    }
}
private actor CalendarAcceptanceEvidence {
    var results: [ToolResult] = []
    func accept(_ event: AgentEvent) {
        if case .result(let tool, let result) = event, tool == "create_calendar_event" { results.append(result) }
    }
}
private actor CalendarAcceptanceCleanup {
    func verifyAndRemove(_ data: [String: JSONValue], expectedTitle: String) throws -> Bool {
        let formatter = ISO8601DateFormatter()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              expectedTitle.hasPrefix("Sotto verification "),
              let id = data["identifier"]?.string,
              let start = data["start"]?.string.flatMap(formatter.date(from:)),
              let end = data["end"]?.string.flatMap(formatter.date(from:)),
              end.timeIntervalSince(start) == 300 else { throw ToolError.denied("No owned test event was available for cleanup.") }
        let store = EKEventStore()
        guard let event = store.event(withIdentifier: id), event.title == expectedTitle,
              !event.isAllDay, event.attendees?.isEmpty != false,
              abs(event.startDate.timeIntervalSince(start)) < 1, abs(event.endDate.timeIntervalSince(end)) < 1 else {
            throw ToolError.denied("The test event changed or could not be verified; it was not removed.")
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [event.calendar])
        let count = store.events(matching: predicate).filter { $0.title == expectedTitle && abs($0.startDate.timeIntervalSince(start)) < 1 }.count
        try store.remove(event, span: .thisEvent, commit: true)
        guard store.event(withIdentifier: id) == nil else { throw ToolError.unavailable("Calendar did not confirm test event removal.") }
        guard count == 1 else { throw ToolError.unavailable("Calendar contained \(count) matching test events instead of one.") }
        return true
    }
}
#endif
