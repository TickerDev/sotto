import Foundation
import AppKit
import SottoTools

public enum AliasKind: String, Codable, CaseIterable, Sendable { case file, folder, application, workflow }
public struct RememberedAlias: Codable, Sendable, Identifiable, Equatable {
    public var id: String { WorkflowDefinition.normalizedName(name) }
    public let name: String
    /// Legacy storage key retained; application/workflow references use bundle ID / UUID.
    public let path: String
    public let kind: AliasKind
    public let revision: Int
    public init(name: String, path: String, kind: AliasKind = .file, revision: Int = 1) {
        self.name = name; self.path = path; self.kind = kind; self.revision = revision
    }
    private enum CodingKeys: String, CodingKey { case name, path, kind, revision }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name); path = try c.decode(String.self, forKey: .path)
        kind = try c.decodeIfPresent(AliasKind.self, forKey: .kind) ?? .file
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
    }
}
public final class RememberedAliasStore: @unchecked Sendable {
    public static let shared = RememberedAliasStore()
    private let defaults: UserDefaults
    private let lock = NSRecursiveLock()
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func all() throws -> [RememberedAlias] { try lock.withLock { try read() } }
    private func read() throws -> [RememberedAlias] {
        guard let data = defaults.data(forKey: "rememberedAliases") else { return [] }
        guard data.count <= 524_288 else { throw ToolError.unavailable("Remembered names exceed their storage limit") }
        do {
            let values = try JSONDecoder().decode([RememberedAlias].self, from: data)
            guard values.count <= 100, Set(values.map(\.id)).count == values.count,
                  values.allSatisfy({ $0.revision > 0 && !$0.id.isEmpty && $0.path.count <= 4096 }) else { throw ToolError.invalid("Invalid remembered names") }
            return values
        } catch { throw ToolError.unavailable("Remembered names could not be read. Existing data was preserved.") }
    }
    private func write(_ values: [RememberedAlias]) throws {
        let data = try JSONEncoder().encode(values)
        guard data.count <= 524_288 else { throw ToolError.invalid("Remembered names exceed their storage limit") }
        defaults.set(data, forKey: "rememberedAliases")
        guard defaults.data(forKey: "rememberedAliases") == data else { throw ToolError.unavailable("Remembered name save could not be verified") }
    }
    @discardableResult public func upsert(_ value: RememberedAlias, expectedRevision: Int) throws -> RememberedAlias {
        try WorkflowDefinition.validateName(value.name)
        guard !value.path.isEmpty, value.path.count <= 4096 else { throw ToolError.invalid("Choose a valid remembered target") }
        return try lock.withLock {
            var values = try read()
            let saved: RememberedAlias
            if let index = values.firstIndex(where: { $0.id == value.id }) {
                guard values[index].revision == expectedRevision, expectedRevision < Int.max else { throw ToolError.denied("This remembered name changed. List remembered names before changing it.") }
                saved = RememberedAlias(name: value.name.trimmingCharacters(in: .whitespacesAndNewlines), path: value.path, kind: value.kind, revision: expectedRevision + 1)
                values[index] = saved
            } else {
                guard expectedRevision == 0 else { throw ToolError.denied("This remembered name was removed. List remembered names again.") }
                guard values.count < 100 else { throw ToolError.invalid("You can remember up to 100 names") }
                saved = RememberedAlias(name: value.name.trimmingCharacters(in: .whitespacesAndNewlines), path: value.path, kind: value.kind)
                values.append(saved)
            }
            try write(values); return saved
        }
    }
    public func remove(_ expected: RememberedAlias) throws {
        try lock.withLock {
            var values = try read()
            guard let index = values.firstIndex(where: { $0.id == expected.id }), values[index] == expected else { throw ToolError.denied("This remembered name changed. Review it before forgetting it.") }
            values.remove(at: index); try write(values)
        }
    }
}
public enum AliasStore {
    public static func all() -> [RememberedAlias] { (try? RememberedAliasStore.shared.all()) ?? [] }
}
struct AliasTool: Tool {
    let action: String
    let store: RememberedAliasStore
    let workflows: WorkflowStore
    init(action: String, store: RememberedAliasStore = .shared, workflows: WorkflowStore = .shared) {
        self.action = action; self.store = store; self.workflows = workflows
    }
    var descriptor: ToolDescriptor {
        var properties: [String: JSONValue] = [:]
        if action != "list" {
            properties["name"] = textProperty("User-chosen remembered name")
            properties["revision"] = .object(["type": .string("integer"), "description": .string("0 for new names; actual revision from aliases.list for changes/removal")])
        }
        if action == "save" {
            properties["kind"] = textProperty("Target kind; defaults to file for compatibility", choices: AliasKind.allCases.map(\.rawValue))
            properties["target_name"] = textProperty("Application-resolved display name; not used for authorization")
            properties["path"] = textProperty("File/folder path, application bundle identifier, or saved workflow UUID")
        }
        return ToolDescriptor(id: "aliases." + action,
            description: action == "list" ? "List actual user-approved remembered file, folder, app and workflow names with revisions." : "Remember/change/forget a user-requested association after approval. List existing names before changing one. Never infer permanent memory from a one-time request. Workflow targets must be actual saved UUIDs; apps must be installed.",
            properties: properties, required: action == "list" ? [] : action == "save" ? ["name", "path"] : ["name"],
            risk: action == "list" ? .read : .consequential, capabilities: [.files])
    }
    private func revision(_ arguments: JSONValue) throws -> Int {
        guard let value = arguments.object?["revision"] else { return 0 }
        guard case .number(let n) = value, n >= 0, n < Double(Int.max) else { throw ToolError.invalid("Use an actual remembered-name revision") }
        return Int(n)
    }
    @MainActor private func canonical(_ arguments: JSONValue) throws -> RememberedAlias {
        let name = arguments.object?["name"]?.string ?? ""
        try WorkflowDefinition.validateName(name)
        let target = arguments.object?["path"]?.string ?? ""
        let kind = AliasKind(rawValue: arguments.object?["kind"]?.string ?? "file") ?? .file
        switch kind {
        case .file, .folder:
            let url = try FilePolicy.url(target)
            let folder = (try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]))
            if kind == .folder && (folder.isDirectory != true || folder.isPackage == true) { throw ToolError.invalid("Choose a folder") }
            return RememberedAlias(name: name, path: url.path, kind: folder.isDirectory == true && folder.isPackage != true ? .folder : .file)
        case .application:
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) != nil else { throw ToolError.unavailable("Choose an installed application") }
        case .workflow:
            guard let id = UUID(uuidString: target), try workflows.all().contains(where: { $0.id == id }) else { throw ToolError.unavailable("Choose an existing saved workflow") }
        }
        return RememberedAlias(name: name, path: kind == .workflow ? UUID(uuidString: target)!.uuidString : target, kind: kind)
    }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue {
        try descriptor.validate(arguments)
        guard action != "list" else { return arguments }
        let name = arguments.object?["name"]?.string ?? ""
        let current = try store.all().first { $0.id == WorkflowDefinition.normalizedName(name) }
        let expected = try revision(arguments)
        if let current { guard current.revision == expected else { throw ToolError.denied("List remembered names before changing or forgetting this association.") } }
        else if action == "remove" || expected != 0 { throw ToolError.invalid("No remembered name matches this request") }
        if action == "save" {
            let value = try await canonical(arguments)
            let label: String
            if value.kind == .workflow { label = try workflows.all().first(where: { $0.id.uuidString == value.path })?.name ?? "Saved workflow" }
            else if value.kind == .application {
                label = await MainActor.run { NSWorkspace.shared.urlForApplication(withBundleIdentifier: value.path)?.deletingPathExtension().lastPathComponent ?? value.path }
            } else { label = value.path }
            return .object(["name": .string(value.name), "kind": .string(value.kind.rawValue), "path": .string(value.path), "target_name": .string(label), "revision": .number(Double(expected))])
        }
        return .object(["name": .string(current!.name), "revision": .number(Double(expected))])
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        if action == "list" {
            return ToolResult("Remembered names", data: .array(try store.all().map {
                .object(["name": .string($0.name), "kind": .string($0.kind.rawValue), "path": .string($0.path), "revision": .number(Double($0.revision))])
            }))
        }
        let expected = try revision(arguments)
        if action == "save" {
            let value = try await canonical(arguments); try Task.checkCancellation()
            let saved = try store.upsert(value, expectedRevision: expected)
            return ToolResult("Remembered “\(saved.name)” locally.", data: .object(["name": .string(saved.name), "revision": .number(Double(saved.revision))]))
        }
        guard let current = try store.all().first(where: { $0.id == WorkflowDefinition.normalizedName(arguments.object?["name"]?.string ?? "") }), current.revision == expected else { throw ToolError.denied("This remembered name changed. List names before forgetting it.") }
        try store.remove(current)
        return ToolResult("Forgot “\(current.name)”.")
    }
}
public struct AliasCommand: Sendable {
    public let tool: String
    public let arguments: JSONValue
    public static func resolve(_ command: String, aliases: [RememberedAlias], workflows: [SavedWorkflow]) -> Self? {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for verb in ["open ", "launch ", "run ", "start ", "begin "] where text.lowercased().hasPrefix(verb) {
            let name = WorkflowDefinition.normalizedName(String(text.dropFirst(verb.count)))
            func variants(_ value: String) -> Set<String> { [value, value.hasPrefix("my ") ? String(value.dropFirst(3)) : value] }
            let matches = aliases.filter { !variants($0.id).isDisjoint(with: variants(name)) }
            if matches.count > 1 { return .init(tool: "ask_user", arguments: .object(["question": .string("More than one remembered name matches. Which one do you mean?")])) }
            guard let alias = matches.first else { return nil }
            switch alias.kind {
            case .application:
                guard ["open ", "launch ", "start "].contains(verb) else { return nil }
                return .init(tool: "apps.open", arguments: .object(["bundle_id": .string(alias.path)]))
            case .workflow:
                guard let id = UUID(uuidString: alias.path), let workflow = workflows.first(where: { $0.id == id }) else { return nil }
                return .init(tool: "workflows.run", arguments: .object(["name": .string(workflow.name), "steps": .array([])]))
            case .file, .folder:
                guard verb == "open " else { return nil }
                var folder: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: (alias.path as NSString).expandingTildeInPath, isDirectory: &folder)
                return .init(tool: alias.kind == .folder || folder.boolValue ? "open_folder" : "files.open", arguments: .object(["path": .string(alias.path)]))
            }
        }
        return nil
    }
}
