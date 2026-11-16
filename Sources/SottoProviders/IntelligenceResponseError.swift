import Foundation

/// Content-free failures: never echo generated arguments or private conversation data.
public enum IntelligenceResponseError: LocalizedError, Sendable {
    case unreadableResponse
    case invalidAction
    public var errorDescription: String? {
        switch self {
        case .unreadableResponse:
            "Sotto couldn’t understand the intelligence response. Try a shorter request, or choose another connection in Intelligence."
        case .invalidAction:
            "The intelligence response didn’t describe a valid action. Try rephrasing your request, or choose another connection in Intelligence."
        }
    }
}
