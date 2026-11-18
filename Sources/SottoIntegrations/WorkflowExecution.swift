import Foundation
import SottoTools

enum WorkflowExecution {
    static func run(_ initial: WorkflowRunRecord, registry: ToolRegistry, journal: WorkflowJournal,
                    progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult {
        // The caller holds this execution's cross-process lease throughout.
        guard !initial.hasUncertainSteps else { throw ToolError.denied("Uncertain workflow actions must be explicitly reviewed and skipped before continuing.") }
        let prepared = try WorkflowDefinition.validate(.array(initial.steps.map(\.definition)), registry: registry)
        var record = initial
        for index in record.steps.indices {
            guard record.steps[index].state == .pending else { continue }
            if Task.isCancelled {
                record.state = .paused; record.note = "Cancelled before the next action started."
                record = try journal.update(record)
                return result(record, message: "Workflow paused. Completed actions will not be repeated.", cancelled: true)
            }
            await progress("Step \(index + 1) of \(record.steps.count)")
            // This durable marker precedes every dispatch. A crash here can only
            // create a conservative uncertainty, never permission to replay.
            record.steps[index].state = .running; record.state = .active; record.note = nil
            record = try journal.update(record)
            let entry = prepared[index]
            let began = ContinuousClock.now
            let outcome: ToolResult
            do {
                outcome = try await withThrowingTaskGroup(of: ToolResult.self) { group in
                    group.addTask { try await entry.0.execute(arguments: entry.1, progress: progress) }
                    group.addTask {
                        try await Task.sleep(for: .seconds(entry.0.descriptor.timeoutSeconds))
                        throw ToolError.unavailable("Action timed out. Its outcome must be checked before continuing.")
                    }
                    defer { group.cancelAll() }
                    guard let first = try await group.next() else { throw CancellationError() }
                    return first
                }
            } catch {
                outcome = ToolResult(error is CancellationError ? "Cancelled; the action may already have taken effect." : error.localizedDescription,
                                     state: error is CancellationError ? .cancelled : .failure)
            }
            let duration = began.duration(to: .now).components
            record.steps[index].durationSeconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            record.steps[index].result = outcome
            record.steps[index].state = outcome.state == .success ? .succeeded : .uncertain
            if outcome.state != .success {
                record.state = .paused; record.note = "Action \(index + 1) needs review: \(outcome.summary)"
            }
            record = try journal.update(record)
            if outcome.state != .success {
                return result(record, message: "Workflow stopped at action \(index + 1): \(outcome.summary) Check this action before continuing; completed actions will not be repeated.", cancelled: outcome.state == .cancelled)
            }
        }
        let skipped = record.steps.contains { $0.state == .skipped }
        record.state = skipped ? .completedWithSkips : .completed
        record.note = skipped ? "Uncertain actions were explicitly skipped; their outcomes remain unverified." : nil
        record = try journal.update(record)
        return result(record, message: skipped ? "Finished the remaining actions. Previously skipped actions remain unverified." : "Completed \(record.steps.count) workflow actions.")
    }
    static func result(_ record: WorkflowRunRecord, message: String, cancelled: Bool = false) -> ToolResult {
        let completed = record.steps.filter { $0.state == .succeeded }.count
        let state: ToolResultState
        if record.state == .completed { state = .success }
        else if completed > 0 || record.steps.contains(where: { $0.state == .skipped || $0.result?.state == .partiallyCompleted }) { state = .partiallyCompleted }
        else { state = cancelled ? .cancelled : .failure }
        return ToolResult(message, data: record.data, state: state)
    }
}
