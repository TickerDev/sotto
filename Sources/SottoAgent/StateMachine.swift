public struct AgentStateMachine: Sendable {
    public private(set) var state: AgentState = .idle
    public init() {}
    @discardableResult public mutating func transition(to next: AgentState) -> Bool {
        if next == state { return true }
        if next == .idle || next == .failed { state = next; return true }
        let allowed: [AgentState]
        switch state {
        case .idle, .completed, .failed, .responded, .awaitingInput: allowed = [.listening, .thinking]
        case .listening: allowed = [.transcribing]
        case .transcribing: allowed = [.thinking]
        case .thinking: allowed = [.executing, .awaitingApproval, .awaitingInput, .responded, .completed]
        case .awaitingApproval: allowed = [.executing, .thinking]
        case .executing: allowed = [.thinking, .awaitingApproval, .awaitingInput, .responded, .completed]
        }
        guard allowed.contains(next) else { return false }
        state = next; return true
    }
}
