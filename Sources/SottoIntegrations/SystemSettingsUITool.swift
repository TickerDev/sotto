import AppKit
import ApplicationServices
import Foundation
import SottoTools

public enum SystemSettingsUIAction: String, CaseIterable, Sendable {
    case on, off, toggle, select, press, status
}

enum SystemSettingsControlMatcher {
    static func score(query: String, candidate: String) -> Int {
        let q = normalize(query)
        let c = normalize(candidate)
        guard !q.isEmpty, !c.isEmpty else { return 0 }
        if q == c { return 100 }
        if c.hasPrefix(q) { return 85 }
        if c.contains(q) { return 70 }
        let qTokens = Set(q.split(separator: " "))
        let cTokens = Set(c.split(separator: " "))
        if !qTokens.isEmpty, qTokens.isSubset(of: cTokens) { return 60 }
        let overlap = qTokens.intersection(cTokens).count
        if overlap > 0 { return overlap * 20 }
        return 0
    }

    static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func desiredPopupCandidates(action: SystemSettingsUIAction, value: String, current: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(trimmed)
        let genericPlaceholders: Set<String> = [
            "", "true", "false", "on", "off", "yes", "no",
            "enable", "enabled", "disable", "disabled", "none", "null", "n a"
        ]
        let offWords: Set<String> = ["never", "off", "disabled", "false", "no"]
        let onWords: Set<String> = ["always", "on", "enabled", "true", "yes"]

        switch action {
        case .select:
            return trimmed.isEmpty ? [] : [trimmed]
        case .on:
            if genericPlaceholders.contains(normalized) || offWords.contains(normalized) {
                return ["Always", "On", "Enabled"]
            }
            return [trimmed]
        case .off:
            if genericPlaceholders.contains(normalized) || onWords.contains(normalized) {
                return ["Never", "Off", "Disabled"]
            }
            return [trimmed]
        case .toggle:
            let cur = normalize(current)
            let isCurrentlyOff = cur == "never" || cur == "off" || cur == "disabled"
                || cur.hasPrefix("never ") || cur.hasPrefix("off ") || cur.hasPrefix("disabled ")
            return isCurrentlyOff ? ["Always", "On", "Enabled"] : ["Never", "Off", "Disabled"]
        default:
            return []
        }
    }

    static func bestPopupOptionIndex(titles: [String], desiredCandidates: [String]) -> Int? {
        guard !desiredCandidates.isEmpty else { return nil }
        let normalizedTitles = titles.map(normalize)
        // 1. Strict priority exact match in candidate order (so "Always" wins before "On").
        for desired in desiredCandidates {
            let q = normalize(desired)
            guard !q.isEmpty else { continue }
            if let index = normalizedTitles.firstIndex(of: q) {
                return index
            }
        }
        // 2. Prefix / multi-word match (skip substring matches for short words like "on"/"off" so "On" never matches "Only on Battery").
        var best: (index: Int, score: Int)?
        for (index, title) in titles.enumerated() {
            let c = normalizedTitles[index]
            guard !c.isEmpty else { continue }
            for desired in desiredCandidates {
                let q = normalize(desired)
                guard !q.isEmpty else { continue }
                let optionScore: Int
                if c.hasPrefix(q + " ") {
                    optionScore = 85
                } else if q.count >= 4 {
                    optionScore = score(query: desired, candidate: title)
                } else {
                    optionScore = 0
                }
                if optionScore >= 60, best == nil || optionScore > best!.score {
                    best = (index, optionScore)
                }
            }
        }
        return best?.index
    }
}

struct SystemSettingsUITool: Tool {
    let descriptor = ToolDescriptor(
        id: "system_settings_ui",
        description: "Inspect or change any macOS System Settings toggle, switch, popup menu, or button via Accessibility when no direct API exists (for example Low Power Mode / battery saver / power saving mode, Reduce Motion, Increase Contrast, Reduce Transparency, VoiceOver, Tap to Click, Natural Scrolling, Stage Manager, or AirDrop). Requires Accessibility permission.",
        properties: [
            "pane": textProperty("System Settings pane name, such as Battery, Accessibility, Focus, Displays, Sound, Trackpad, Keyboard, General, Desktop & Dock, Lock Screen, Notifications, or Privacy & Security."),
            "control": textProperty("Setting control label inside the pane, such as Low Power Mode, Reduce Motion, Increase Contrast, Reduce Transparency, or Tap to click."),
            "action": textProperty("Action to perform", choices: SystemSettingsUIAction.allCases.map(\.rawValue)),
            "value": textProperty("Leave empty for on/off/toggle/status. Only set for select (e.g. Only on Battery) or slider percentage.")
        ],
        required: ["pane", "control", "action"],
        risk: .reversible,
        capabilities: [.settings, .accessibility]
    )

    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        try Task.checkCancellation()
        guard let paneRaw = arguments.object?["pane"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !paneRaw.isEmpty,
              let controlRaw = arguments.object?["control"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !controlRaw.isEmpty,
              let actionRaw = arguments.object?["action"]?.string,
              let action = SystemSettingsUIAction(rawValue: actionRaw) else {
            throw ToolError.invalid("Specify the System Settings pane, control label, and action.")
        }
        let value = arguments.object?["value"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard AXIsProcessTrusted() else {
            throw ToolError.denied("Allow Sotto in System Settings → Privacy & Security → Accessibility.")
        }
        guard let pane = SystemSettingsPaneCatalog.resolve(paneRaw, controlHint: controlRaw)
                ?? SystemSettingsPaneCatalog.resolve(controlRaw) else {
            throw ToolError.invalid("Unknown System Settings pane: \(paneRaw)")
        }

        let opened = await MainActor.run { NSWorkspace.shared.open(pane.url) }
        guard opened else {
            throw ToolError.unavailable("Could not open \(pane.title) in System Settings.")
        }

        // Wait up to 3.5 seconds for System Settings to render the requested pane's controls.
        for _ in 0..<35 {
            try Task.checkCancellation()
            if let result = try await MainActor.run(body: {
                try SystemSettingsAXDriver.perform(paneTitle: pane.title, controlQuery: controlRaw, action: action, value: value)
            }) {
                return result
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        throw ToolError.unavailable("Opened \(pane.title) in System Settings, but could not find “\(controlRaw)”.")
    }
}

@MainActor
private enum SystemSettingsAXDriver {
    private static let interactiveRoles: Set<String> = ["AXCheckBox", "AXSwitch", "AXRadioButton", "AXPopUpButton", "AXSlider", "AXButton"]

    private struct Candidate {
        let element: AXUIElement
        let role: String
        let label: String
        let score: Int
    }

    static func perform(paneTitle: String, controlQuery: String, action: SystemSettingsUIAction, value: String) throws -> ToolResult? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return nil
        }

        var candidates: [Candidate] = []
        for window in windows {
            collectCandidates(in: window, query: controlQuery, depth: 0, into: &candidates)
        }
        guard let best = candidates.max(by: { $0.score < $1.score }), best.score >= 40 else {
            return nil
        }

        let label = best.label.isEmpty ? controlQuery : best.label
        switch best.role {
        case "AXCheckBox", "AXSwitch", "AXRadioButton":
            let current = boolValue(of: best.element)
            if action == .status {
                return ToolResult("\(label) is \(current == true ? "on" : current == false ? "off" : "available")", data: .object(["control": .string(label), "enabled": current.map(JSONValue.bool) ?? .null]))
            }
            let target: Bool
            switch action {
            case .on: target = true
            case .off: target = false
            case .toggle, .press: target = !(current ?? false)
            default: throw ToolError.invalid("Use on, off, toggle, or status for \(label).")
            }
            if let current, current == target {
                return ToolResult("\(label) is already \(target ? "on" : "off")", data: .object(["control": .string(label), "enabled": .bool(target)]))
            }
            let err = AXUIElementPerformAction(best.element, kAXPressAction as CFString)
            guard err == .success else {
                throw ToolError.unavailable("Accessibility could not toggle \(label) (error \(err.rawValue)).")
            }
            Thread.sleep(forTimeInterval: 0.12)
            let updated = boolValue(of: best.element) ?? target
            return ToolResult("\(updated ? "Turned on" : "Turned off") \(label) in \(paneTitle)", data: .object(["control": .string(label), "enabled": .bool(updated)]))

        case "AXPopUpButton":
            let current = stringValue(of: best.element) ?? ""
            if action == .status {
                return ToolResult("\(label) is set to \(current.isEmpty ? "unknown" : current)", data: .object(["control": .string(label), "value": .string(current)]))
            }
            let desiredCandidates = SystemSettingsControlMatcher.desiredPopupCandidates(action: action, value: value, current: current)
            guard !desiredCandidates.isEmpty else {
                if action == .select {
                    throw ToolError.invalid("Specify which option to select for \(label).")
                }
                throw ToolError.invalid("Use select, on, off, toggle, or status for \(label).")
            }

            let openErr = AXUIElementPerformAction(best.element, kAXPressAction as CFString)
            guard openErr == .success else {
                throw ToolError.unavailable("Accessibility could not open \(label) menu.")
            }
            var menuItems: [(element: AXUIElement, title: String)] = []
            for _ in 0..<8 {
                Thread.sleep(forTimeInterval: 0.05)
                menuItems = collectMenuItems(under: best.element)
                if !menuItems.isEmpty { break }
            }
            guard let chosenIndex = SystemSettingsControlMatcher.bestPopupOptionIndex(titles: menuItems.map(\.title), desiredCandidates: desiredCandidates) else {
                AXUIElementPerformAction(best.element, kAXCancelAction as CFString)
                let choices = menuItems.map(\.title).filter { !$0.isEmpty }.joined(separator: ", ")
                let desiredSummary = desiredCandidates.first ?? value
                throw ToolError.invalid(choices.isEmpty ? "Option “\(desiredSummary)” was not found for \(label)." : "Option “\(desiredSummary)” was not found for \(label). Available options: \(choices)")
            }
            let chosenItem = menuItems[chosenIndex]
            let pressErr = AXUIElementPerformAction(chosenItem.element, kAXPressAction as CFString)
            guard pressErr == .success else {
                AXUIElementPerformAction(best.element, kAXCancelAction as CFString)
                throw ToolError.unavailable("Could not select “\(chosenItem.title)” for \(label).")
            }
            var updated = chosenItem.title
            for _ in 0..<6 {
                Thread.sleep(forTimeInterval: 0.05)
                if let liveValue = stringValue(of: best.element),
                   !liveValue.isEmpty,
                   SystemSettingsControlMatcher.normalize(liveValue) == SystemSettingsControlMatcher.normalize(chosenItem.title) {
                    updated = liveValue
                    break
                }
            }
            return ToolResult("\(label) set to \(updated) in \(paneTitle)", data: .object(["control": .string(label), "value": .string(updated)]))

        case "AXSlider":
            let current = numberValue(of: best.element)
            if action == .status {
                return ToolResult("\(label) is \(current.map { String(Int(round($0 * 100))) + "%" } ?? "set")")
            }
            let pctString = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pct = Double(pctString), pct.isFinite else {
                throw ToolError.invalid("Specify a numeric value for \(label).")
            }
            let minVal = (attribute(best.element, kAXMinValueAttribute) as? NSNumber)?.doubleValue ?? 0
            let maxVal = (attribute(best.element, kAXMaxValueAttribute) as? NSNumber)?.doubleValue ?? 1
            let scaled = maxVal <= 1.0 ? max(minVal, min(maxVal, pct / 100.0)) : max(minVal, min(maxVal, pct))
            let err = AXUIElementSetAttributeValue(best.element, kAXValueAttribute as CFString, NSNumber(value: scaled))
            guard err == .success else {
                throw ToolError.unavailable("Accessibility could not set \(label).")
            }
            return ToolResult("\(label) updated in \(paneTitle)")

        default:
            if action == .status {
                return ToolResult("\(label) is available in \(paneTitle)")
            }
            let err = AXUIElementPerformAction(best.element, kAXPressAction as CFString)
            guard err == .success else {
                throw ToolError.unavailable("Accessibility could not press \(label).")
            }
            return ToolResult("Activated \(label) in \(paneTitle)", data: .object(["control": .string(label)]))
        }
    }

    private static func collectCandidates(in element: AXUIElement, query: String, depth: Int, into results: inout [Candidate]) {
        guard depth <= 18 else { return }
        let identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
        // Skip the left navigation sidebar when matching setting controls inside the pane content.
        if identifier == "com.apple.settings.sidebar.collectionView" { return }

        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        if interactiveRoles.contains(role) {
            let label = resolvedLabel(for: element)
            let score = SystemSettingsControlMatcher.score(query: query, candidate: label)
            if score > 0 {
                results.append(Candidate(element: element, role: role, label: label, score: score))
            }
        }

        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                collectCandidates(in: child, query: query, depth: depth + 1, into: &results)
            }
        }
    }

    private static func collectMenuItems(under element: AXUIElement, depth: Int = 0) -> [(element: AXUIElement, title: String)] {
        guard depth <= 5 else { return [] }
        var items: [(AXUIElement, String)] = []
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        if role == "AXMenuItem" {
            let title = (attribute(element, kAXTitleAttribute) as? String)
                ?? (attribute(element, kAXDescriptionAttribute) as? String)
                ?? ""
            items.append((element, title))
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children {
                items.append(contentsOf: collectMenuItems(under: child, depth: depth + 1))
            }
        }
        return items
    }

    private static func resolvedLabel(for element: AXUIElement) -> String {
        if let titleEl = attribute(element, kAXTitleUIElementAttribute),
           CFGetTypeID(titleEl) == AXUIElementGetTypeID() {
            let axTitleEl = unsafeDowncast(titleEl, to: AXUIElement.self)
            if let value = attribute(axTitleEl, kAXValueAttribute) as? String, !value.isEmpty { return value }
            if let title = attribute(axTitleEl, kAXTitleAttribute) as? String, !title.isEmpty { return title }
        }
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, "AXLabel"] {
            if let text = attribute(element, key) as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return ""
    }

    private static func boolValue(of element: AXUIElement) -> Bool? {
        if let number = attribute(element, kAXValueAttribute) as? NSNumber {
            return number.intValue != 0
        }
        return nil
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        if let text = attribute(element, kAXValueAttribute) as? String { return text }
        if let text = attribute(element, kAXTitleAttribute) as? String { return text }
        return nil
    }

    private static func numberValue(of element: AXUIElement) -> Double? {
        (attribute(element, kAXValueAttribute) as? NSNumber)?.doubleValue
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return err == .success ? value : nil
    }
}
