import Foundation
import Observation
import SottoTools

/// In-memory, single-use intent. Never encoded into preferences, history or diagnostics.
/// A monotonic deadline avoids extending authorization if the system clock changes.
@MainActor @Observable public final class PendingIntelligenceRequest {
    public struct Intent: Sendable {
        public let id: UUID
        public let text: String
        public let context: [JSONValue]
        let deadline: ContinuousClock.Instant
    }
    public private(set) var intent: Intent?
    public init() {}
    @discardableResult public func preserve(_ text: String, context: [JSONValue], now: ContinuousClock.Instant = .now) -> UUID {
        let intent = Intent(id: UUID(), text: text, context: context, deadline: now.advanced(by: .seconds(300)))
        self.intent = intent
        return intent.id
    }
    public func take(_ id: UUID, connectionVerified: Bool, now: ContinuousClock.Instant = .now) -> Intent? {
        guard let intent, intent.id == id else { return nil }
        guard now < intent.deadline else { self.intent = nil; return nil }
        guard connectionVerified else { return nil }
        self.intent = nil
        return intent
    }
    public func discard() { intent = nil }
}
