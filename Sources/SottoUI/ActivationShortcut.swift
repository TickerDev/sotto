import AppKit

public struct ActivationShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16?
    public let modifiers: UInt64
    public let keyLabel: String
    static let relevantFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]
    static let functionKeys: [UInt16: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
    static let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    public static let `default` = ActivationShortcut(keyCode: 49, flags: [.maskControl, .maskAlternate], keyLabel: "Space")

    public init(keyCode: UInt16?, flags: CGEventFlags, keyLabel: String = "") {
        self.keyCode = keyCode; self.modifiers = flags.intersection(Self.relevantFlags).rawValue
        self.keyLabel = keyCode == nil ? "" : keyLabel
    }
    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
    var isValid: Bool {
        guard modifiers == flags.intersection(Self.relevantFlags).rawValue else { return false }
        guard let keyCode else { return modifiers != 0 }
        return keyCode < 128 && keyCode != 53 && !Self.modifierKeys.contains(keyCode) &&
            (modifiers != 0 || Self.functionKeys[keyCode] != nil) &&
            !keyLabel.isEmpty && keyLabel.count <= 24 && keyLabel.rangeOfCharacter(from: .controlCharacters) == nil
    }
    public var display: String {
        var parts: [String] = []
        for (flag, name) in [(CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"), (.maskSecondaryFn, "fn")] where flags.contains(flag) { parts.append(name) }
        if keyCode != nil { parts.append(keyLabel) }
        return parts.joined(separator: " ")
    }
    static func legacy(modifierIndex: Int, keyCode: Int64) -> Self {
        let flags: [CGEventFlags] = [[.maskControl, .maskAlternate], [.maskCommand, .maskShift], [.maskControl, .maskSecondaryFn]]
        return Self(keyCode: keyCode == 79 ? 79 : 49, flags: flags[min(max(modifierIndex, 0), 2)], keyLabel: keyCode == 79 ? "F18" : "Space")
    }
    static func capture(_ event: NSEvent) -> Self {
        let special: [UInt16: String] = [49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "Delete", 117: "Forward Delete", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"]
        let name = Self.functionKeys[event.keyCode] ?? special[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        return Self(keyCode: event.keyCode, flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)), keyLabel: name)
    }
}

/// Pure timing policy; audio starts on the first press. Only a short first tap
/// waits for the double-tap window, preventing a premature submission in between taps.
struct ShortcutGesture {
    enum Effect: Equatable { case beginHold, handsFree, submit }
    enum Phase: Equatable { case idle, held(Double), waiting(Double), handsFree }
    private(set) var phase: Phase = .idle
    let tapDuration: Double
    let doubleTapInterval: Double
    init(doubleTapInterval: Double = 0.5, tapDuration: Double = 0.5) {
        self.doubleTapInterval = doubleTapInterval; self.tapDuration = tapDuration
    }
    var deadline: Double? { if case .waiting(let deadline) = phase { deadline } else { nil } }
    mutating func press(at now: Double) -> [Effect] {
        switch phase {
        case .idle: phase = .held(now); return [.beginHold]
        case .waiting(let deadline) where now <= deadline: phase = .handsFree; return [.handsFree]
        case .waiting: phase = .held(now); return [.submit, .beginHold]
        case .held, .handsFree: return []
        }
    }
    mutating func release(at now: Double) -> [Effect] {
        guard case .held(let start) = phase else { return [] }
        if now - start <= tapDuration { phase = .waiting(now + doubleTapInterval); return [] }
        phase = .idle; return [.submit]
    }
    mutating func expire(at now: Double) -> [Effect] {
        guard case .waiting(let deadline) = phase, now >= deadline else { return [] }
        phase = .idle; return [.submit]
    }
    mutating func reset() { phase = .idle }
}
