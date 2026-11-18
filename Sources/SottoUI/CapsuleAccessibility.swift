import AppKit
import SottoAgent

enum CapsuleAccessibility {
    static func announcement(state: AgentState, status: String) -> String? {
        switch state {
        case .completed, .responded: "\(status). Result available in Sotto."
        case .failed: "Sotto couldn’t finish. Review the error and recovery action."
        case .awaitingInput: "Sotto has a question. Review it and choose Reply."
        case .awaitingApproval: "Sotto needs your approval. Review the action before continuing."
        default: nil // Never announce every waveform or provisional-word revision.
        }
    }
    @MainActor static func announce(state: AgentState, status: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled, let message = announcement(state: state, status: status) else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}
