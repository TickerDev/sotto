import Foundation
import SottoTools

struct ListWorkflowsTool: Tool {
    let store: WorkflowStore
    init(store: WorkflowStore = .shared) { self.store = store }
    let descriptor = ToolDescriptor(id: "workflows.list", description: "List actual saved workflows with identifiers, revisions and ordered actions. Use these references when editing/removing; ask if the name is ambiguous.", properties: [:], required: [], risk: .read, capabilities: [.automation])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        let values = try store.all()
        return ToolResult("Found \(values.count) saved workflows", data: .object(["workflows": .array(values.map { value in
            .object(["id": .string(value.id.uuidString), "name": .string(value.name), "revision": .number(Double(value.revision)), "steps": value.steps])
        })]))
    }
}
struct SaveWorkflowTool: Tool {
    let registry: ToolRegistry
    let store: WorkflowStore
    init(registry: ToolRegistry, store: WorkflowStore = .shared) { self.registry = registry; self.store = store }
    var descriptor: ToolDescriptor {
        ToolDescriptor(id: "workflows.save", description: "Save a user-requested reusable workflow after approval of its exact name and complete actions. Saving never executes the actions. Use id empty/revision 0 for new workflows; use actual id/revision from workflows.list to edit. Never silently remember an inferred routine.", properties: [
            "id": textProperty("Existing workflow identifier, or empty to create"),
            "revision": .object(["type": .string("integer"), "description": .string("Existing revision, or 0 to create")]),
            "name": textProperty("User-chosen workflow name"),
            "steps": WorkflowDefinition.stepsSchema
        ], required: ["id", "revision", "name", "steps"], risk: .consequential, capabilities: [.automation])
    }
    private func candidate(_ arguments: JSONValue) throws -> (SavedWorkflow, Int?) {
        try descriptor.validate(arguments)
        guard let name = arguments.object?["name"]?.string, case .number(let revision) = arguments.object?["revision"],
              revision >= 0, revision < Double(Int.max), let raw = arguments.object?["id"]?.string,
              let steps = arguments.object?["steps"] else { throw ToolError.invalid("Provide a workflow name, actions and valid revision") }
        try WorkflowDefinition.validateName(name)
        _ = try WorkflowDefinition.validate(steps, registry: registry)
        let current = try store.all()
        let targetID = UUID(uuidString: raw)
        guard !current.contains(where: { $0.id != targetID && WorkflowDefinition.normalizedName($0.name) == WorkflowDefinition.normalizedName(name) }) else { throw ToolError.invalid("A workflow already uses this name. List workflows before editing it, or choose another name.") }
        if raw.isEmpty {
            guard revision == 0 else { throw ToolError.invalid("New workflows use revision 0") }
            return (SavedWorkflow(name: name, steps: steps), nil)
        }
        guard let id = UUID(uuidString: raw), revision >= 1 else { throw ToolError.invalid("Choose an existing workflow from workflows.list") }
        guard let existing = current.first(where: { $0.id == id }), existing.revision == Int(revision) else { throw ToolError.denied("This workflow changed or was removed. List workflows again before editing.") }
        return (SavedWorkflow(name: name, steps: steps, id: id), Int(revision))
    }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        _ = try candidate(arguments)
        return arguments
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        let (value, revision) = try candidate(arguments)
        try Task.checkCancellation()
        let saved = try store.upsert(value, expectedRevision: revision, registry: registry)
        return ToolResult("Saved “\(saved.name)”. Its actions have not been run.", data: .object(["id": .string(saved.id.uuidString), "name": .string(saved.name), "revision": .number(Double(saved.revision)), "steps": saved.steps]))
    }
}
struct RemoveWorkflowTool: Tool {
    let store: WorkflowStore
    init(store: WorkflowStore = .shared) { self.store = store }
    let descriptor = ToolDescriptor(id: "workflows.remove", description: "Forget a saved workflow after approval. Use its exact identifier, title and revision from workflows.list. Does not undo or repeat any past actions.", properties: ["id": textProperty("Existing workflow identifier"), "name": textProperty("Exact current workflow name"), "revision": .object(["type": .string("integer")])], required: ["id", "name", "revision"], risk: .consequential, capabilities: [.automation])
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        try descriptor.validate(arguments)
        guard let raw = arguments.object?["id"]?.string, let id = UUID(uuidString: raw),
              let name = arguments.object?["name"]?.string, case .number(let revision) = arguments.object?["revision"],
              let current = try store.all().first(where: { $0.id == id }), current.name == name,
              Double(current.revision) == revision else { throw ToolError.denied("This workflow changed or was removed. List workflows before removing it.") }
        return arguments
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        guard let raw = arguments.object?["id"]?.string, let id = UUID(uuidString: raw),
              let name = arguments.object?["name"]?.string, case .number(let revision) = arguments.object?["revision"], revision >= 1, revision < Double(Int.max) else { throw ToolError.invalid("Choose the saved workflow to remove") }
        try store.remove(id: id, name: name, expectedRevision: Int(revision))
        return ToolResult("Removed saved workflow “\(name)”. Past actions were not changed.")
    }
}
