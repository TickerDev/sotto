import Foundation
import SottoAgent

@MainActor final class VoicePreparationController {
    private var tracker = SpeechPauseTracker()
    private var pause: Task<Void, Never>?
    private var pending: Task<PreparedAgentTurn?, Never>?
    private var prepare: (@MainActor @Sendable (String) async -> PreparedAgentTurn?)?
    private var requestedKey = ""
    private var generation = UUID()
    private var attempts = 0
    func begin(prepare: @escaping @MainActor @Sendable (String) async -> PreparedAgentTurn?) {
        cancel(); self.prepare = prepare; tracker = SpeechPauseTracker(); attempts = 0
    }
    func transcript(_ text: String, at time: Double = ProcessInfo.processInfo.systemUptime) {
        let sameRequest = PreparedAgentTurn.requestKey(tracker.text) == PreparedAgentTurn.requestKey(text)
        if tracker.transcript(text, at: time) && !sameRequest { invalidate() }
        schedule()
    }
    func audio(_ value: Float, at time: Double = ProcessInfo.processInfo.systemUptime) {
        if tracker.audio(value, at: time) { invalidate() }
        if tracker.deadline == nil { pause?.cancel(); pause = nil }
        else { schedule() }
    }
    private func invalidate() {
        generation = UUID(); pause?.cancel(); pause = nil; pending?.cancel(); pending = nil; requestedKey = ""
    }
    private func schedule() {
        guard prepare != nil, attempts < 2, pause == nil, let deadline = tracker.deadline,
              requestedKey != PreparedAgentTurn.requestKey(tracker.text) else { return }
        let generation = generation
        pause = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime)))
            guard !Task.isCancelled, let self, generation == self.generation, let prepare = self.prepare else { return }
            self.pause = nil
            let text = self.tracker.text; self.requestedKey = PreparedAgentTurn.requestKey(text)
            // Deterministic native routing already avoids inference at release.
            guard NativeCommandProvider(command: text) == nil else { return }
            self.attempts += 1
            let inference = Task { await prepare(text) }
            let timeout = Task { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { inference.cancel() } }
            self.pending = Task {
                let value = await withTaskCancellationHandler { await inference.value } onCancel: { inference.cancel() }
                timeout.cancel()
                return Task.isCancelled ? nil : value
            }
        }
    }
    /// A finalized request may await a matching in-flight first step. Different
    /// words discard it; the runtime checks provider/context/age again.
    func take(for final: String) -> Task<PreparedAgentTurn?, Never>? {
        pause?.cancel(); pause = nil; prepare = nil
        guard requestedKey == PreparedAgentTurn.requestKey(final) else { invalidate(); return nil }
        let result = pending; pending = nil; requestedKey = ""; return result
    }
    func cancel() { invalidate(); prepare = nil }
}
