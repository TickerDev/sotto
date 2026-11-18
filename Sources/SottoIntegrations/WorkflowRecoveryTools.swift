import Foundation
import SottoTools

struct ListWorkflowRunsTool: Tool {
    let journal: WorkflowJournal
    init(journal: WorkflowJournal = .shared) { self.journal = journal }
    let descriptor = ToolDescriptor(id: "workflows.runs", description: "List local workflow executions and recovery state. Completed actions are never replayed. Running/uncertain actions require explicit user review before skipping and continuing.", properties: [:], required: [], risk: .read, capabilities: [.automation])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        let records = try journal.records()
        return ToolResult("Found \(records.count) workflow execution records", data: .object(["runs": .array(records.map(\.data))]))
    }
}
struct ResumeWorkflowTool: Tool {
    let registry: ToolRegistry
    let journal: WorkflowJournal
    init(registry: ToolRegistry, journal: WorkflowJournal = .shared) { self.registry = registry; self.journal = journal }
    var descriptor: ToolDescriptor {
        var remainingSchema = WorkflowDefinition.stepsSchema.object!
        remainingSchema["minItems"] = .number(0) // Reviewing the final uncertain action may leave no pending actions.
        return ToolDescriptor(id: "workflows.resume", description: "Continue an actual interrupted execution after approval of remaining actions. Never repeats succeeded steps. Set skip_uncertain only after the user explicitly says they checked uncertain actions and wants them skipped; these are never retried or declared successful. Reference an actual ID from workflows.runs.", properties: [
            "id": textProperty("Actual execution UUID"),
            "skip_uncertain": .object(["type": .string("boolean"), "description": .string("Only true after explicit user review/confirmation to skip uncertain actions")]),
            "expected_revision": .object(["type": .string("integer")]),
            "steps": .object(remainingSchema),
            "skipped_steps": .object(["type": .string("array"), "items": .object(["type": .string("object")])])
        ], required: ["id", "skip_uncertain"], risk: .consequential, capabilities: [.automation], timeoutSeconds: 120)
    }
    private func reference(_ arguments: JSONValue) throws -> (UUID, Bool) {
        try descriptor.validate(arguments)
        guard let raw = arguments.object?["id"]?.string, let id = UUID(uuidString: raw),
              case .bool(let skip) = arguments.object?["skip_uncertain"] else { throw ToolError.invalid("Choose an actual workflow execution") }
        return (id, skip)
    }
    private func skipped(_ record: WorkflowRunRecord) -> [JSONValue] {
        record.steps.enumerated().filter { $0.element.state == .running || $0.element.state == .uncertain }
            .map { .object(["step": .number(Double($0.offset + 1)), "definition": $0.element.definition]) }
    }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        let (id, skip) = try reference(arguments)
        let record = try journal.load(id)
        guard !record.terminal else { throw ToolError.invalid("This execution has already finished. It will not be run again.") }
        if record.hasUncertainSteps && !skip { throw ToolError.denied("An earlier action may already have taken effect. Ask the user to check it and explicitly confirm skipping it before continuing. It will not be retried.") }
        _ = try WorkflowDefinition.validate(.array(record.steps.map(\.definition)), registry: registry)
        return .object(["id": .string(id.uuidString), "skip_uncertain": .bool(skip), "expected_revision": .number(Double(record.revision)),
                        "steps": .array(record.remaining), "skipped_steps": .array(skipped(record))])
    }
    func execute(arguments: JSONValue) async throws -> ToolResult { try await execute(arguments: arguments, progress: { _ in }) }
    func execute(arguments: JSONValue, progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult {
        let (id, skip) = try reference(arguments)
        try Task.checkCancellation()
        let lease = try journal.lease(id)
        defer { withExtendedLifetime(lease) {} }
        var record = try journal.load(id)
        guard !record.terminal, case .number(let revision) = arguments.object?["expected_revision"], revision == Double(record.revision),
              arguments.object?["steps"] == .array(record.remaining),
              arguments.object?["skipped_steps"] == .array(skipped(record)) else { throw ToolError.denied("Recovery changed or has not been reviewed. Review the remaining actions before continuing.") }
        guard !record.hasUncertainSteps || skip else { throw ToolError.denied("Uncertain actions cannot be repeated") }
        _ = try WorkflowDefinition.validate(.array(record.steps.map(\.definition)), registry: registry)
        for index in record.steps.indices where record.steps[index].state == .running || record.steps[index].state == .uncertain {
            record.steps[index].state = .skipped
            record.steps[index].result = ToolResult("Explicitly skipped after user review; the outcome remains unverified.", state: .partiallyCompleted)
        }
        record.state = .active; record.note = nil
        record = try journal.update(record)
        return try await WorkflowExecution.run(record, registry: registry, journal: journal, progress: progress)
    }
}
