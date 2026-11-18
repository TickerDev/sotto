import Foundation
import SottoTools

/// Deliberately narrow: preserve the title, demand AM/PM and a duration. Other
/// date expressions use the reasoning/clarification path, never guessed dates.
enum CalendarCreationCommand {
    static func arguments(_ command: String, now: Date, calendar: Calendar) -> JSONValue? {
        let pattern = #"^(?:please\s+)?(?:schedule|create (?:an? )?(?:calendar )?event(?: called)?|add (?:an? )?(?:calendar )?event(?: called)?)\s+(.{1,256}?)\s+(today|tomorrow)\s+at\s+(\d{1,2})(?::([0-5]\d))?\s*(am|pm)\s+for\s+(\d{1,3})\s+(minutes?|hours?)[.!?]?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) else { return nil }
        func group(_ index: Int) -> String { Range(match.range(at: index), in: command).map { String(command[$0]) } ?? "" }
        let title = group(1).trimmingCharacters(in: .whitespacesAndNewlines)
        // Negation/compound requests need genuine reasoning, not this shortcut.
        guard !title.isEmpty, !title.lowercased().contains(" and "), !title.lowercased().contains(" then "),
              let hour = Int(group(3)), (1...12).contains(hour), let duration = Int(group(6)), duration > 0 else { return nil }
        let minutes = duration * (group(7).lowercased().hasPrefix("hour") ? 60 : 1)
        guard minutes <= 7 * 24 * 60,
              let day = calendar.date(byAdding: .day, value: group(2).lowercased() == "tomorrow" ? 1 : 0, to: calendar.startOfDay(for: now)) else { return nil }
        let targetHour = hour % 12 + (group(5).lowercased() == "pm" ? 12 : 0), minute = Int(group(4)) ?? 0
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = targetHour; parts.minute = minute; parts.second = 0
        guard let start = calendar.date(from: parts), start > now,
              calendar.component(.hour, from: start) == targetHour, calendar.component(.minute, from: start) == minute,
              let end = calendar.date(byAdding: .minute, value: minutes, to: start) else { return nil }
        let beforeDay = day.addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: beforeDay, matching: parts, matchingPolicy: .strict, repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: beforeDay, matching: parts, matchingPolicy: .strict, repeatedTimePolicy: .last), first == last else { return nil }
        let formatter = ISO8601DateFormatter()
        return .object(["title": .string(title), "start": .string(formatter.string(from: start)), "end": .string(formatter.string(from: end))])
    }
}
