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
    public static func toolAction(name: String, arguments: JSONValue) -> Self {
        Self(steps: [Step(tool: name, arguments: arguments)])
    }
    public static func fileAction(path: String, reveal: Bool) -> Self {
        Self(steps: [Step(tool: "open_file", arguments: .object(["path": .string(path), "action": .string(reveal ? "reveal" : "open")]))])
    }
    public init?(command: String, now: Date = Date(), calendar: Calendar = .current) {
        if let image = ImageSearchIntent(command) {
            steps = [Step(tool: "web.images", arguments: .object(["query": .string(image.query), "presentation": .string(image.gallery ? "gallery" : "single")]))]; return
        }
        if let arguments = CalendarCreationCommand.arguments(command.trimmingCharacters(in: .whitespacesAndNewlines), now: now, calendar: calendar) {
            steps = [Step(tool: "create_calendar_event", arguments: arguments)]; return
        }
        let normalized = Self.normalizeCommandText(command)
        guard !normalized.isEmpty else { return nil }
        if let corrected = Self.correctedFolderStep(normalized) {
            steps = [corrected]; return
        }
        let clauses = Self.splitClauses(normalized)
        if (1...3).contains(clauses.count) {
            let parsed = clauses.compactMap { Self.parse(Self.stripLeadingFillers($0), now: now, calendar: calendar) }
            if parsed.count == clauses.count {
                steps = parsed
                return
            }
        }
        // Fallback: split on ", " only when every resulting clause is a known native command.
        if normalized.contains(", ") {
            let commaClauses = normalized
                .replacingOccurrences(of: ", ", with: "\u{0000}")
                .components(separatedBy: "\u{0000}")
                .map(Self.stripEdgePunctuation)
                .filter { !$0.isEmpty }
            if (2...3).contains(commaClauses.count) {
                let parsed = commaClauses.compactMap { Self.parse(Self.stripLeadingFillers($0), now: now, calendar: calendar) }
                if parsed.count == commaClauses.count {
                    steps = parsed
                    return
                }
            }
        }
        return nil
    }

    private static let folderRequestPattern = #"(?:(?:(?:can|could|would|will) you|please)[\s,]+){0,3}open (?:my |the )?(downloads|documents|desktop)(?: folder)?(?:,? please)?"#

    private static func folderStep(_ text: String) -> Step? {
        guard let expression = try? NSRegularExpression(pattern: "^\(folderRequestPattern)$"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let path = ["downloads": "~/Downloads", "documents": "~/Documents", "desktop": "~/Desktop"][String(text[range])] else { return nil }
        return Step(tool: "open_folder", arguments: .object(["path": .string(path)]))
    }

    /// A correction replaces an earlier destination; it is not a conjunction.
    /// Match the entire request and only known folder commands. Never discard
    /// arbitrary prefixes, file names, negations or unsupported trailing work.
    private static func correctedFolderStep(_ text: String) -> Step? {
        let folder = folderRequestPattern
        let separator = #"[\s,.;:!?—–-]+(?:actually|no(?:[\s,]+i mean)?|i mean)[\s,:—–-]+"#
        let pattern = "^\(folder)(?:\(separator)\(folder)){1,2}(?: instead)?$"
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let expression = try? NSRegularExpression(pattern: separator),
              let boundary = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(boundary.range, in: text) else { return nil }
        var replacement = String(text[range.upperBound...])
        if replacement.hasSuffix(" instead") { replacement.removeLast(" instead".count) }
        return folderStep(replacement)
    }

    private static func normalizeCommandText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "wi-fi", with: "wifi")
            .replacingOccurrences(of: "low-power", with: "low power")
            .replacingOccurrences(of: "auto-hide", with: "autohide")
            .replacingOccurrences(of: "auto hide", with: "autohide")
            .replacingOccurrences(of: "voice over", with: "voiceover")
            .replacingOccurrences(of: "privacy and security", with: "privacy & security")
            .replacingOccurrences(of: "desktop and dock", with: "desktop & dock")
            .replacingOccurrences(of: "users and groups", with: "users & groups")
            .replacingOccurrences(of: "airdrop and handoff", with: "airdrop & handoff")
            .replacingOccurrences(of: "date and time", with: "date & time")
            .replacingOccurrences(of: "language and region", with: "language & region")
        return stripEdgePunctuation(stripLeadingFillers(trimmed))
    }

    private static func stripEdgePunctuation(_ value: String) -> String {
        let punctuation = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?;:"))
        return value.trimmingCharacters(in: punctuation)
    }

    private static func stripLeadingFillers(_ raw: String) -> String {
        var text = stripEdgePunctuation(raw)
        let fillers = [
            "all right", "alright", "okay", "ok", "sure", "well",
            "hey sotto", "hey", "sotto", "let's", "lets", "now", "just", "also", "then",
            "please", "can you", "could you", "would you", "will you", "go ahead and"
        ]
        var changed = true
        while changed {
            changed = false
            for filler in fillers {
                if text.hasPrefix(filler + " ") || text.hasPrefix(filler + ", ") || text.hasPrefix(filler + ",") {
                    text = stripEdgePunctuation(String(text.dropFirst(filler.count)))
                    changed = true
                    break
                }
            }
        }
        return text
    }

    private static func splitClauses(_ text: String) -> [String] {
        var current = text
        let separators = [", and also ", " and also ", ", and then ", " and then ", ", also ", ", then ", "; ", ", and ", " and "]
        // Replace separators with a null sentinel so all conjunctions split consistently.
        for separator in separators {
            current = current.replacingOccurrences(of: separator, with: "\u{0000}")
        }
        return current
            .components(separatedBy: "\u{0000}")
            .map(stripEdgePunctuation)
            .filter { !$0.isEmpty }
    }

    private static func parse(_ text: String, now: Date, calendar: Calendar) -> Step? {
        if ["what tab am i on", "what is my current browser tab", "what webpage am i viewing", "show my current browser tab"].contains(text) {
            return Step(tool: "browser.currentTab", arguments: .object([:]))
        }
        if ["read this webpage", "read the current webpage", "read this browser page", "read the current browser page"].contains(text) {
            return Step(tool: "browser.readPage", arguments: .object([:]))
        }
        if text.hasPrefix("run "), text.hasSuffix(" workflow") {
            let name = String(text.dropFirst(4))
            return Step(tool: "workflows.run", arguments: .object(["name": .string(name), "steps": .array([])]))
        }
        if ["pause my music", "pause music"].contains(text) {
            return Step(tool: "media.playPause", arguments: .object(["action": .string("pause")]))
        }
        if ["show my active timers", "show active timers", "list timers", "show my timers"].contains(text) {
            return Step(tool: "timers.list", arguments: .object([:]))
        }
        if ["what application am i using", "what app am i using"].contains(text) {
            return Step(tool: "screen.context", arguments: .object([:]))
        }
        if ["open safari", "launch safari"].contains(text) {
            return Step(tool: "applications", arguments: .object(["action": .string("open"), "bundle_id": .string("com.apple.Safari")]))
        }
        let timerPattern = #"^set (?:a |an |the )?(\w+)[ -](second|minute|hour)s? timer$"#
        if let regex = try? NSRegularExpression(pattern: timerPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let numberRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text) {
            let words: [String: Double] = ["one": 1, "two": 2, "three": 3, "five": 5, "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30, "sixty": 60]
            if let amount = Double(text[numberRange]) ?? words[String(text[numberRange])], amount > 0 {
                let multiplier: Double = text[unitRange] == "hour" ? 3600 : text[unitRange] == "minute" ? 60 : 1
                return Step(tool: "timers.start", arguments: .object(["seconds": .number(amount * multiplier), "name": .string("")]))
            }
        }
        for (day, offset) in [("today", 0), ("tomorrow", 1)] {
            let phrases = ["what's on my calendar \(day)", "what’s on my calendar \(day)", "what is on my calendar \(day)", "show my calendar \(day)", "show my agenda \(day)", "what do i have on my calendar \(day)"]
            if phrases.contains(text), let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
               let end = calendar.date(byAdding: .day, value: 1, to: start) {
                let formatter = ISO8601DateFormatter()
                return Step(tool: "list_calendar_events", arguments: .object(["start": .string(formatter.string(from: start)), "end": .string(formatter.string(from: end))]))
            }
        }
        if let folder = folderStep(text) { return folder }
        if ["find my latest pdf", "find my most recent pdf", "find my latest pdf file"].contains(text) {
            return Step(tool: "find_files", arguments: .object(["name": .string(".pdf")]))
        }
        for prefix in ["find my ", "find the file ", "find a file named ", "find a file called "] where text.hasPrefix(prefix) {
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
        if let settingStep = parseSettingCommand(text) { return settingStep }
        return nil
    }

    private static func parseSettingCommand(_ raw: String) -> Step? {
        let text = stripLeadingFillers(raw)

        // Direct toggle/enable/disable/status settings
        let directAliases: [(names: [String], setting: String, invertedOff: Bool)] = [
            (["night shift"], "night_shift", false),
            (["true tone"], "true_tone", false),
            (["dark mode", "dark appearance"], "dark_mode", false),
            (["light mode", "light appearance"], "dark_mode", true),
            (["wifi"], "wifi", false),
            (["bluetooth"], "bluetooth", false),
            (["dock autohide", "autohide dock", "autohiding dock", "the dock autohide"], "dock_autohide", false),
            (["dock magnification"], "dock_magnification", false),
            (["hidden files"], "show_hidden_files", false),
            (["file extensions", "filename extensions"], "show_file_extensions", false)
        ]

        for entry in directAliases {
            for name in entry.names {
                if ["turn on \(name)", "turn \(name) on", "enable \(name)", "activate \(name)", "switch on \(name)", "switch \(name) on", "switch to \(name)", "put \(name) on", "set \(name) on", "set \(name) to on"].contains(text) {
                    return Step(tool: "system_settings", arguments: .object(["setting": .string(entry.setting), "action": .string(entry.invertedOff ? "off" : "on")]))
                }
                if ["turn off \(name)", "turn \(name) off", "disable \(name)", "deactivate \(name)", "switch off \(name)", "switch \(name) off", "put \(name) off", "set \(name) off", "set \(name) to off"].contains(text) {
                    return Step(tool: "system_settings", arguments: .object(["setting": .string(entry.setting), "action": .string(entry.invertedOff ? "on" : "off")]))
                }
                if ["toggle \(name)", "switch \(name)"].contains(text) {
                    return Step(tool: "system_settings", arguments: .object(["setting": .string(entry.setting), "action": .string("toggle")]))
                }
                if ["is \(name) on", "check \(name)", "\(name) status", "what is \(name)"].contains(text) {
                    return Step(tool: "system_settings", arguments: .object(["setting": .string(entry.setting), "action": .string("status")]))
                }
            }
        }

        // Finder & Dock shorthands
        if ["show hidden files", "show hidden files in finder"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("show_hidden_files"), "action": .string("on")]))
        }
        if ["hide hidden files", "hide hidden files in finder"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("show_hidden_files"), "action": .string("off")]))
        }
        if ["show file extensions", "show filename extensions"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("show_file_extensions"), "action": .string("on")]))
        }
        if ["hide file extensions", "hide filename extensions"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("show_file_extensions"), "action": .string("off")]))
        }
        if ["hide the dock", "hide dock"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("dock_autohide"), "action": .string("on")]))
        }
        if ["show the dock", "show dock"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("dock_autohide"), "action": .string("off")]))
        }

        // Volume, Audio & Mute
        let audioNouns = ["volume", "audio", "sound", "audio volume", "sound volume", "volume level", "audio level", "sound level"]
        if ["mute", "mute my mac"].contains(text) || audioNouns.contains(where: { text == "mute \($0)" || text == "mute the \($0)" }) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("mute"), "action": .string("on")]))
        }
        if ["unmute", "unmute my mac"].contains(text) || audioNouns.contains(where: { text == "unmute \($0)" || text == "unmute the \($0)" }) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("mute"), "action": .string("off")]))
        }
        if text == "louder" || audioNouns.contains(where: {
            ["turn up \($0)", "turn up the \($0)", "turn \($0) up", "turn the \($0) up", "increase \($0)", "increase the \($0)", "raise \($0)", "raise the \($0)", "\($0) up"].contains(text)
        }) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("volume"), "action": .string("up")]))
        }
        if text == "quieter" || audioNouns.contains(where: {
            ["turn down \($0)", "turn down the \($0)", "turn \($0) down", "turn the \($0) down", "decrease \($0)", "decrease the \($0)", "lower \($0)", "lower the \($0)", "\($0) down"].contains(text)
        }) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("volume"), "action": .string("down")]))
        }
        if audioNouns.contains(where: {
            ["what is \($0)", "what is the \($0)", "what's \($0)", "what's the \($0)", "check \($0)", "check the \($0)", "\($0) status"].contains(text)
        }) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("volume"), "action": .string("status")]))
        }
        let volumePrefixes = audioNouns.flatMap { noun in
            [
                "set \(noun) to ", "set the \(noun) to ",
                "set \(noun) at ", "set the \(noun) at ",
                "change \(noun) to ", "change the \(noun) to ",
                "adjust \(noun) to ", "adjust the \(noun) to ",
                "put \(noun) to ", "put the \(noun) to ",
                "put \(noun) at ", "put the \(noun) at ",
                "make \(noun) ", "make the \(noun) ",
                "turn \(noun) to ", "turn the \(noun) to ",
                "turn \(noun) up to ", "turn the \(noun) up to ",
                "turn \(noun) down to ", "turn the \(noun) down to ",
                "\(noun) to ", "\(noun) "
            ]
        }
        if let pct = extractPercentage(text, prefixes: volumePrefixes) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("volume"), "action": .string("set"), "value": .string(pct)]))
        }

        // Brightness
        if ["turn up brightness", "turn up the brightness", "turn brightness up", "turn the brightness up", "increase brightness", "increase the brightness", "brightness up", "brighter"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("brightness"), "action": .string("up")]))
        }
        if ["turn down brightness", "turn down the brightness", "turn brightness down", "turn the brightness down", "decrease brightness", "decrease the brightness", "lower brightness", "lower the brightness", "brightness down", "dimmer"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("brightness"), "action": .string("down")]))
        }
        if ["what is the brightness", "what's the brightness", "what is brightness", "check brightness", "check the brightness", "brightness status"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("brightness"), "action": .string("status")]))
        }
        if let pct = extractPercentage(text, prefixes: ["set brightness to ", "set the brightness to ", "set display brightness to ", "set brightness at ", "set the brightness at ", "turn brightness to ", "turn the brightness to ", "brightness to ", "brightness "]) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("brightness"), "action": .string("set"), "value": .string(pct)]))
        }
        if let pct = extractPercentage(text, prefixes: ["set night shift warmth to ", "set night shift to ", "night shift warmth to "]) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("night_shift"), "action": .string("set"), "value": .string(pct)]))
        }

        // Display Sleep / Screen Saver / Lock Screen (uses consequential system_power tool)
        if ["sleep display", "sleep the display", "turn off display", "turn off the display", "turn off screen", "turn off the screen"].contains(text) {
            return Step(tool: "system_power", arguments: .object(["action": .string("sleep_display")]))
        }
        if ["start screen saver", "start screensaver", "turn on screen saver", "turn on the screen saver"].contains(text) {
            return Step(tool: "system_power", arguments: .object(["action": .string("screen_saver")]))
        }
        if ["lock screen", "lock the screen", "lock my screen", "lock my mac"].contains(text) {
            return Step(tool: "system_power", arguments: .object(["action": .string("lock_screen")]))
        }

        // Accessibility-backed System Settings UI controls (triggers Accessibility permission flow if needed)
        let uiControls: [(phrases: [String], pane: String, control: String)] = [
            (["low power mode", "low power", "battery saver", "battery saver mode", "battery saving", "battery saving mode", "power saver", "power saver mode", "power saving", "power saving mode", "energy saver", "energy saving"], "Battery", "Low Power Mode"),
            (["reduce motion", "reduced motion"], "Accessibility", "Reduce motion"),
            (["increase contrast", "high contrast"], "Accessibility", "Increase contrast"),
            (["reduce transparency", "reduced transparency"], "Accessibility", "Reduce transparency"),
            (["invert colors"], "Accessibility", "Invert colors"),
            (["color filters"], "Accessibility", "Color filters"),
            (["differentiate without color"], "Accessibility", "Differentiate without color"),
            (["voiceover"], "Accessibility", "VoiceOver"),
            (["tap to click"], "Trackpad", "Tap to click"),
            (["natural scrolling"], "Trackpad", "Natural scrolling"),
            (["stage manager"], "Desktop & Dock", "Stage Manager")
        ]
        for item in uiControls {
            for phrase in item.phrases {
                if ["turn on \(phrase)", "turn \(phrase) on", "enable \(phrase)", "activate \(phrase)", "switch on \(phrase)", "switch \(phrase) on", "put on \(phrase)", "put \(phrase) on", "set \(phrase) on", "set \(phrase) to on"].contains(text) {
                    return Step(tool: "system_settings_ui", arguments: .object(["pane": .string(item.pane), "control": .string(item.control), "action": .string("on")]))
                }
                if ["turn off \(phrase)", "turn \(phrase) off", "disable \(phrase)", "deactivate \(phrase)", "switch off \(phrase)", "switch \(phrase) off", "put \(phrase) off", "set \(phrase) off", "set \(phrase) to off"].contains(text) {
                    return Step(tool: "system_settings_ui", arguments: .object(["pane": .string(item.pane), "control": .string(item.control), "action": .string("off")]))
                }
                if ["toggle \(phrase)"].contains(text) {
                    return Step(tool: "system_settings_ui", arguments: .object(["pane": .string(item.pane), "control": .string(item.control), "action": .string("toggle")]))
                }
                if ["is \(phrase) on", "check \(phrase)", "\(phrase) status"].contains(text) {
                    return Step(tool: "system_settings_ui", arguments: .object(["pane": .string(item.pane), "control": .string(item.control), "action": .string("status")]))
                }
            }
        }

        // Open System Settings panes
        if ["open system settings", "open settings", "open system preferences"].contains(text) {
            return Step(tool: "system_settings", arguments: .object(["setting": .string("open_pane"), "action": .string("open"), "value": .string("System Settings")]))
        }
        if text.hasPrefix("open "), (text.hasSuffix(" settings") || text.hasSuffix(" preferences")) {
            let suffix = text.hasSuffix(" settings") ? " settings" : " preferences"
            let pane = String(text.dropFirst("open ".count).dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if !pane.isEmpty, pane != "sotto" {
                return Step(tool: "system_settings", arguments: .object(["setting": .string("open_pane"), "action": .string("open"), "value": .string(pane)]))
            }
        }

        return nil
    }

    private static func extractPercentage(_ text: String, prefixes: [String]) -> String? {
        for prefix in prefixes where text.hasPrefix(prefix) {
            let remainder = String(text.dropFirst(prefix.count))
                .replacingOccurrences(of: "percent", with: "")
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let number = Double(remainder), number.isFinite, (0...100).contains(number) {
                return String(Int(round(number)))
            }
        }
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
            if results.count == outputs.count, results.allSatisfy({ $0.state == .success }), outputs.count < steps.count {
                let step = steps[outputs.count]
                continuation.yield(.output([.object(["type": .string("function_call"), "call_id": .string(UUID().uuidString), "name": .string(step.tool), "arguments": .string(step.arguments.encoded)])]))
            } else {
                var messages = results.map { result -> String in
                    if let agenda = result.data.object?["agenda"]?.string { return agenda }
                    if result.data.object?["page_ref"] != nil, let text = result.data.object?["text"]?.string {
                        return result.summary + "\n\n" + text
                    }
                    if let matches = FileSearchResults.decode(result.data) {
                        return matches.files.isEmpty ? "No matching files found in the locations Sotto could search. Try another name." : "Here are the best matches. Choose a file to open it."
                    }
                    if case .array(let paths) = result.data {
                        return paths.first?.string.map { "Most recently modified match: \(($0 as NSString).lastPathComponent)\n\($0)" } ?? "No matching indexed PDFs were found."
                    }
                    return result.summary
                }
                if results.count != outputs.count || results.contains(where: { $0.state != .success }) {
                    let failureReason = outputs
                        .compactMap { $0.object?["output"]?.string }
                        .first { $0.hasPrefix("Tool failed: ") }
                        .map { String($0.dropFirst("Tool failed: ".count)) } ?? results.first(where: { $0.state != .success })?.summary
                    if steps.count > 1 {
                        if let failureReason, !failureReason.isEmpty {
                            messages.append("The remaining actions were stopped because an action failed: \(failureReason)")
                        } else {
                            messages.append("The remaining actions were stopped because an action failed.")
                        }
                    } else if let failureReason, !failureReason.isEmpty {
                        messages.append(failureReason)
                    } else {
                        messages.append("The action could not finish.")
                    }
                }
                let message = messages.joined(separator: "\n")
                continuation.yield(.text(message))
                continuation.yield(.output([.object(["role": .string("assistant"), "content": .string(message)])]))
            }
            continuation.finish()
        }
    }
}
