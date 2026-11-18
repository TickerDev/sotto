import Foundation
import SottoTools

public struct SavedWorkflow: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var steps: JSONValue
    public let revision: Int
    public init(name: String, steps: JSONValue, id: UUID = UUID(), revision: Int = 1) {
        self.id = id; self.name = name; self.steps = steps; self.revision = revision
    }
    private enum CodingKeys: String, CodingKey { case id, name, steps, revision }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        steps = try c.decode(JSONValue.self, forKey: .steps)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
    }
}

/// Process-local serialization and optimistic revisions prevent a stale editor or
/// model request overwriting a workflow changed since it was reviewed.
public final class WorkflowStore: @unchecked Sendable {
    public static let shared = WorkflowStore()
    private let defaults: UserDefaults
    private let lock = NSRecursiveLock()
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func all() throws -> [SavedWorkflow] { try lock.withLock { try read() } }
    private func read() throws -> [SavedWorkflow] {
        guard let data = defaults.data(forKey: "personalWorkflows") else { return [] }
        guard data.count <= 262_144 else { throw ToolError.unavailable("Saved workflows exceed their storage limit") }
        do {
            let values = try JSONDecoder().decode([SavedWorkflow].self, from: data)
            guard values.count <= 50, Set(values.map(\.id)).count == values.count,
                  Set(values.map { WorkflowDefinition.normalizedName($0.name) }).count == values.count,
                  values.allSatisfy({ $0.revision > 0 }) else { throw ToolError.invalid("Invalid workflow storage") }
            return values
        } catch { throw ToolError.unavailable("Saved workflows could not be read. Existing data was preserved.") }
    }
    private func write(_ values: [SavedWorkflow]) throws {
        let data = try JSONEncoder().encode(values)
        guard data.count <= 262_144 else { throw ToolError.invalid("Saved workflows exceed their storage limit") }
        defaults.set(data, forKey: "personalWorkflows")
        guard defaults.data(forKey: "personalWorkflows") == data else { throw ToolError.unavailable("Workflow save could not be verified") }
    }
    @discardableResult public func upsert(_ value: SavedWorkflow, expectedRevision: Int?, registry: ToolRegistry) throws -> SavedWorkflow {
        try WorkflowDefinition.validateName(value.name)
        _ = try WorkflowDefinition.validate(value.steps, registry: registry)
        return try lock.withLock {
            var values = try read()
            let name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !values.contains(where: { $0.id != value.id && WorkflowDefinition.normalizedName($0.name) == WorkflowDefinition.normalizedName(name) }) else { throw ToolError.invalid("A workflow already uses this name. Choose it to edit, or use another name.") }
            let saved: SavedWorkflow
            if let index = values.firstIndex(where: { $0.id == value.id }) {
                guard expectedRevision == values[index].revision, values[index].revision < Int.max else { throw ToolError.denied("This workflow changed since it was opened. Reload it before saving.") }
                saved = SavedWorkflow(name: name, steps: value.steps, id: value.id, revision: values[index].revision + 1)
                values[index] = saved
            } else {
                guard expectedRevision == nil else { throw ToolError.denied("This workflow was removed. Reload the workflow list.") }
                guard values.count < 50 else { throw ToolError.invalid("You can save up to 50 workflows") }
                saved = SavedWorkflow(name: name, steps: value.steps, id: value.id)
                values.append(saved)
            }
            try write(values)
            return saved
        }
    }
    public func remove(id: UUID, name: String, expectedRevision: Int) throws {
        try lock.withLock {
            var values = try read()
            guard let index = values.firstIndex(where: { $0.id == id }),
                  values[index].name == name, values[index].revision == expectedRevision else { throw ToolError.denied("This workflow changed or was removed. Reload it before removing.") }
            values.remove(at: index)
            try write(values)
        }
    }
}
public enum PersonalAutomation {
    public static func workflows() -> [SavedWorkflow] { (try? WorkflowStore.shared.all()) ?? [] }
    /// Resolve only exact user-approved names after a simple run/start/begin verb.
    /// Ambiguous possessive variants are left to clarification.
    public static func workflow(for command: String, workflows: [SavedWorkflow]? = nil) -> SavedWorkflow? {
        var text = command.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in ["run ", "start ", "begin "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            let query = WorkflowDefinition.normalizedName(text)
            func variants(_ name: String) -> Set<String> {
                let normalized = WorkflowDefinition.normalizedName(name)
                return [normalized, normalized.hasPrefix("my ") ? String(normalized.dropFirst(3)) : normalized]
            }
            let matches = (workflows ?? self.workflows()).filter { !variants($0.name).isDisjoint(with: variants(query)) }
            return matches.count == 1 ? matches[0] : nil
        }
        return nil
    }
}
