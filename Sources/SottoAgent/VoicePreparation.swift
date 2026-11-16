import Foundation
import SottoTools

public struct PreparedAgentTurn: Sendable {
    let text: String
    let context: [JSONValue]
    let previousConversations: [[JSONValue]]
    let providerKey: String
    let output: [JSONValue]
    let reply: String
    let created: ContinuousClock.Instant
    init(text: String, context: [JSONValue], previousConversations: [[JSONValue]] = [], providerKey: String, output: [JSONValue], reply: String = "", created: ContinuousClock.Instant = .now) {
        self.text = text; self.context = context; self.previousConversations = previousConversations; self.providerKey = providerKey; self.output = output; self.reply = reply
        self.created = created
    }
    public static func requestKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public func matches(text: String, context: [JSONValue], previousConversations: [[JSONValue]] = [], providerKey: String) -> Bool {
        !providerKey.isEmpty && self.providerKey == providerKey && self.context == context && self.previousConversations == previousConversations &&
        Self.requestKey(self.text) == Self.requestKey(text) && created.duration(to: .now) < .seconds(15)
    }
}

/// Acoustic activity and transcript stability both matter. Silence alone does
/// not authorize an action. The caller may only use this to prepare inference.
public struct SpeechPauseTracker: Sendable {
    public private(set) var text = ""
    private var lastVoice = 0.0
    private var lastRevision = 0.0
    private var voiced = false
    public init() {}
    @discardableResult public mutating func transcript(_ value: String, at now: Double) -> Bool {
        guard text != value else { return false }
        text = value; lastRevision = now; return true
    }
    @discardableResult public mutating func audio(_ level: Float, at now: Double) -> Bool {
        let active = level > 0.08
        let resumed = active && !voiced
        if active { lastVoice = now }
        voiced = active
        return resumed
    }
    public var deadline: Double? {
        guard !voiced, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 else { return nil }
        return max(lastVoice, lastRevision) + 0.65
    }
}
