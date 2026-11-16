import Foundation
import SottoTools
import SottoProviders

/// A bounded grammar for known native actions, including short conjunctions.
/// Every clause must match; arbitrary or ambiguous requests go to reasoning.
/// The runtime still validates, authorizes, executes and records each action.
public struct NativeCommandProvider: ReasoningProvider {
    private struct Step: Sendable { let tool: String; let arguments: JSONValue }
    private let steps: [Step]
    public var tool: String { steps[0].tool }
    public var arguments: JSONValue { steps[0].arguments }
    private init(steps: [Step]) { self.steps = steps }
    public static func fileAction(path: String, reveal: Bool) -> Self {
        Self(steps: [Step(tool: "open_file", arguments: .object(["path": .string(path), "action": .string(reveal ? "reveal" : "open")]))])
    }
    public init?(command: String, now: Date = Date(), calendar: Calendar = .current) {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        let clauses = text.components(separatedBy: " and ")
        guard (1...3).contains(clauses.count) else { return nil }
        let parsed = clauses.compactMap { Self.parse($0.trimmingCharacters(in: .whitespaces), now: now, calendar: calendar) }
        guard parsed.count == clauses.count else { return nil }
        steps = parsed
    }
    private static func parse(_ text: String, now: Date, calendar: Calendar) -> Step? {
        for (day, offset) in [("today", 0), ("tomorrow", 1)] {
            let phrases = ["what's on my calendar \(day)", "what’s on my calendar \(day)", "what is on my calendar \(day)", "show my calendar \(day)", "show my agenda \(day)", "what do i have on my calendar \(day)"]
            if phrases.contains(text), let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
               let end = calendar.date(byAdding: .day, value: 1, to: start) {
                let formatter = ISO8601DateFormatter()
                return Step(tool: "list_calendar_events", arguments: .object(["start": .string(formatter.string(from: start)), "end": .string(formatter.string(from: end))]))
            }
        }
        let folders = ["downloads": "~/Downloads", "documents": "~/Documents", "desktop": "~/Desktop"]
        for (name, path) in folders {
            if ["open my \(name) folder", "open \(name)", "open \(name) folder", "open my \(name)"].contains(text) {
                return Step(tool: "open_folder", arguments: .object(["path": .string(path)]))
            }
        }
        if ["find my latest pdf", "find my most recent pdf", "find my latest pdf file"].contains(text) {
            return Step(tool: "find_files", arguments: .object(["name": .string(".pdf")]))
        }
        for prefix in ["find my ", "find the file ", "find a file named ", "find a file called ", "can you find my ", "please find my "] where text.hasPrefix(prefix) {
            var name = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            for qualifier in ["most recent ", "latest "] where name.hasPrefix(qualifier) { name = String(name.dropFirst(qualifier.count)) }
            if !name.isEmpty, name.count <= 120, !name.contains(" in "), !name.contains(" from "), !name.contains(" then ") {
                return Step(tool: "find_files", arguments: .object(["name": .string(name)]))
            }
        }
        let playback: [String: String] = [
            "resume music on spotify": "play", "resume my music on spotify": "play",
            "play music on spotify": "play", "resume spotify": "play", "play spotify": "play",
            "pause music on spotify": "pause", "pause spotify": "pause"
        ]
        if let action = playback[text] { return Step(tool: "spotify", arguments: .object(["action": .string(action)])) }
        return nil
    }
    public func models() async throws -> [ModelInfo] { [] }
    public func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let outputs = input.filter { $0.object?["type"]?.string == "function_call_output" }
            let results = outputs.compactMap { item -> ToolResult? in
                guard let data = item.object?["output"]?.string?.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(ToolResult.self, from: data)
            }
            if results.count == outputs.count, outputs.count < steps.count {
                let step = steps[outputs.count]
                continuation.yield(.output([.object(["type": .string("function_call"), "call_id": .string(UUID().uuidString), "name": .string(step.tool), "arguments": .string(step.arguments.encoded)])]))
            } else {
                var messages = results.map { result -> String in
                    if let agenda = result.data.object?["agenda"]?.string { return agenda }
                    if let matches = FileSearchResults.decode(result.data) {
                        return matches.files.isEmpty ? "No matching files found in the locations Sotto could search. Try another name." : "Here are the best matches. Choose a file to open it."
                    }
                    if case .array(let paths) = result.data {
                        return paths.first?.string.map { "Most recently modified match: \(($0 as NSString).lastPathComponent)\n\($0)" } ?? "No matching indexed PDFs were found."
                    }
                    return result.summary
                }
                if results.count != outputs.count {
                    messages.append("The remaining actions were stopped because an action failed.")
                }
                let message = messages.joined(separator: "\n")
                continuation.yield(.text(message))
                continuation.yield(.output([.object(["role": .string("assistant"), "content": .string(message)])]))
            }
            continuation.finish()
        }
    }
}
