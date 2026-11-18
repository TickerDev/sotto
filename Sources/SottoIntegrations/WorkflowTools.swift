import Foundation
import SottoTools

struct ShortcutsTool: Tool {
    let action: String
    var descriptor: ToolDescriptor { ToolDescriptor(id: "shortcuts." + action, description: action == "list" ? "List Apple Shortcuts using the public shortcuts CLI." : "Run a named Apple Shortcut after explicit approval. A Shortcut may have broad effects; process completion does not verify those effects.", properties: action == "run" ? ["name": textProperty("Exact existing shortcut name")] : [:], required: action == "run" ? ["name"] : [], risk: action == "run" ? .consequential : .read, capabilities: [.automation], timeoutSeconds: 30) }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let output = try await AppleScriptExecutor().shortcuts(action == "list" ? ["list"] : ["run", arguments.object?["name"]?.string ?? ""])
        if action == "list" { return ToolResult("Available Apple Shortcuts", data: .array(output.split(separator: "\n").map { .string(String($0)) })) }
        return ToolResult("Shortcuts finished running. Its application-specific effects could not be independently verified.", data: .string(String(output.prefix(4000))), state: .partiallyCompleted)
    }
}

/// Approval shows the complete proposed sequence. Restrict steps to ordinary,
/// reversible native actions; never nest workflows, scripts or sensitive reads.
struct WorkflowTool: Tool {
    let registry: ToolRegistry
    let store: WorkflowStore
    let journal: WorkflowJournal
    init(registry: ToolRegistry, store: WorkflowStore = .shared, journal: WorkflowJournal = .shared) {
        self.registry = registry; self.store = store; self.journal = journal
    }
    static let allowed = WorkflowDefinition.allowed
    var descriptor: ToolDescriptor {
        var schema = WorkflowDefinition.stepsSchema.object!
        schema.removeValue(forKey: "minItems") // Saved workflow references supply an empty inline array.
        return ToolDescriptor(id: "workflows.run", description: "Run 1–10 ordered native actions after approval of the complete sequence. Use name with empty steps to run a saved workflow, or empty name with explicit steps. Stops on incomplete actions; no scripts, nested workflows or automatic replay.", properties: [
            "name": textProperty("Exact saved workflow name, or empty for inline steps"),
            "steps": .object(schema), "label": textProperty("Display label; application resolves saved names before approval")
        ], required: ["name", "steps"], risk: .consequential, capabilities: [.automation], timeoutSeconds: 120)
    }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        try descriptor.validate(arguments)
        let resolved = try resolve(arguments)
        _ = try WorkflowDefinition.validate(resolved, registry: registry)
        return .object(["name": .string(""), "steps": resolved, "label": .string(arguments.object?["name"]?.string?.isEmpty == false ? arguments.object!["name"]!.string! : "Workflow")])
    }
    private func resolve(_ arguments: JSONValue) throws -> JSONValue {
        let name = arguments.object?["name"]?.string ?? ""
        let supplied = arguments.object?["steps"] ?? .null
        guard !name.isEmpty else { return supplied }
        guard case .array(let inline) = supplied, inline.isEmpty else { throw ToolError.invalid("Choose a saved workflow or explicit actions, not both") }
        let matches = try store.all().filter { WorkflowDefinition.normalizedName($0.name) == WorkflowDefinition.normalizedName(name) }
        guard matches.count == 1 else { throw ToolError.invalid("No unique saved workflow has this name. Ask which workflow to run.") }
        return matches[0].steps
    }
    func execute(arguments: JSONValue) async throws -> ToolResult { try await execute(arguments: arguments, progress: { _ in }) }
    func execute(arguments: JSONValue, progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let steps = try resolve(arguments)
        _ = try WorkflowDefinition.validate(steps, registry: registry)
        guard case .array(let values) = steps else { throw ToolError.invalid("Invalid workflow") }
        try Task.checkCancellation()
        let record = try journal.create(name: arguments.object?["label"]?.string ?? "Workflow", steps: values)
        let lease = try journal.lease(record.id)
        defer { withExtendedLifetime(lease) {} }
        return try await WorkflowExecution.run(record, registry: registry, journal: journal, progress: progress)
    }
}
