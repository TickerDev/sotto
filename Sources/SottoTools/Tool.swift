import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var encoded: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "null"
    }
}
public enum Risk: String, Sendable { case read, reversible, consequential }
public enum Capability: String, Sendable { case files, applications, automation, reminders, calendar, contacts, mail, notes, settings, accessibility, web, timers, clipboard, screen, audio, system }
public struct ToolDescriptor: Sendable {
    public let id: String
    public var providerName: String { id.replacingOccurrences(of: ".", with: "__") }
    public var name: String {
        switch id {
        case "mail.accounts": return "Find your Apple Mail accounts"
        case "mail.search": return "Find inbox messages"
        case "mail.read": return "Read an inbox message"
        case "appleNotes.list": return "List Apple Notes"
        case "appleNotes.search": return "Find an Apple Note"
        case "appleNotes.read": return "Read an Apple Note"
        case "appleNotes.create": return "Create an Apple Note"
        case "appleNotes.update": return "Update an Apple Note"
        case "browser.currentTab": return "Identify the current browser tab"
        case "browser.readPage": return "Read the approved browser page"
        case "browser.find": return "Find text on the approved page"
        case "browser.openLink": return "Open a page link"
        default: return id.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    public let timeoutSeconds: Double
    public let permissions: [String]
    public let verification: String
    public let undo: String?
    public var cancellation: String { "Cooperative cancellation; a native action already accepted by macOS may still complete." }
    public let description: String
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue
    public let risk: Risk
    public let capabilities: [Capability]
    public init(id: String, description: String, properties: [String: JSONValue], required: [String], risk: Risk, capabilities: [Capability], timeoutSeconds: Double = 30, permissions: [String] = [], verification: String = "Native adapter checks the observable result; see TOOLS.md for limits.", undo: String? = nil) {
        self.timeoutSeconds = timeoutSeconds
        self.permissions = permissions.isEmpty ? capabilities.compactMap {
            switch $0 {
            case .contacts: return "Contacts access"
            case .calendar: return "Calendar full access"
            case .reminders: return "Reminders full access"
            case .accessibility: return "Accessibility"
            case .files: return "macOS access to requested file locations"
            default: return nil
            }
        } : permissions
        self.verification = verification; self.undo = undo
        self.id = id; self.description = description; self.risk = risk; self.capabilities = capabilities
        inputSchema = .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)])
        outputSchema = .object(["type": .string("object"), "required": .array(["state", "summary", "data"].map(JSONValue.string)), "properties": .object(["state": textProperty("Execution state", choices: ["success", "failure", "cancelled", "permissionRequired", "clarificationRequired", "partiallyCompleted", "unsupported"]), "summary": .object(["type": .string("string")]), "data": .object([:])])])
    }
    public func validate(_ arguments: JSONValue) throws {
        guard let object = arguments.object, let schema = inputSchema.object,
              let properties = schema["properties"]?.object else { throw ToolError.invalid("Expected an object") }
        let required: [JSONValue]
        if case .array(let values) = schema["required"] { required = values } else { required = [] }
        for key in required.compactMap(\.string) where object[key] == nil { throw ToolError.invalid("Missing \(key)") }
        for (key, value) in object {
            guard let definition = properties[key]?.object else { throw ToolError.invalid("Unknown parameter \(key)") }
            switch definition["type"]?.string {
            case "string": guard value.string != nil else { throw ToolError.invalid("\(key) must be text") }
            case "number", "integer":
                guard case .number(let n) = value, n.isFinite,
                      definition["type"]?.string != "integer" || n.rounded() == n else { throw ToolError.invalid("\(key) must be a finite number") }
            case "boolean": guard case .bool = value else { throw ToolError.invalid("\(key) must be boolean") }
            case "object": guard value.object != nil else { throw ToolError.invalid("\(key) must be an object") }
            case "array": guard case .array = value else { throw ToolError.invalid("\(key) must be an array") }
            default: break
            }
            if case .array(let choices) = definition["enum"], !choices.contains(value) { throw ToolError.invalid("Invalid \(key)") }
            var textLimit = 4096
            if case .number(let declared) = definition["maxLength"], declared.isFinite, declared.rounded() == declared, declared >= 1, declared <= 16_000 { textLimit = Int(declared) }
            if let text = value.string, text.count > textLimit { throw ToolError.invalid("Parameter too long") }
        }
    }
}
public enum ToolResultState: String, Codable, Sendable { case success, failure, cancelled, permissionRequired, clarificationRequired, partiallyCompleted, unsupported }
public struct ToolResult: Codable, Sendable, Equatable {
    public let state: ToolResultState
    public let summary: String
    public let data: JSONValue
    public init(_ summary: String, data: JSONValue = .null, state: ToolResultState = .success) { self.summary = summary; self.data = data; self.state = state }
    private enum CodingKeys: String, CodingKey { case summary, data, state }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decode(String.self, forKey: .summary)
        data = try c.decodeIfPresent(JSONValue.self, forKey: .data) ?? .null
        state = try c.decodeIfPresent(ToolResultState.self, forKey: .state) ?? .success
    }
    public var encoded: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "{}" }
}
public protocol Tool: Sendable {
    var descriptor: ToolDescriptor { get }
    /// True only when resolving the immutable approval snapshot itself needs
    /// native access. Ordinary tools retain preflight validation before prompts.
    var requiresPermissionForAuthorization: Bool { get }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue
    func execute(arguments: JSONValue) async throws -> ToolResult
    func execute(arguments: JSONValue, progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult
}
public extension Tool {
    var requiresPermissionForAuthorization: Bool { false }
    func authorizationArguments(_ arguments: JSONValue) async throws -> JSONValue { arguments }
    func execute(arguments: JSONValue, progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult {
        try await execute(arguments: arguments)
    }
}
public struct ToolRegistry: Sendable {
    private let tools: [String: any Tool]
    public init(_ tools: [any Tool]) { self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.descriptor.id, $0) }) }
    public var descriptors: [ToolDescriptor] { tools.values.map(\.descriptor).sorted { $0.id < $1.id } }
    public func tool(_ id: String) throws -> any Tool { guard let t = tools[id] else { throw ToolError.invalid("Unknown tool: \(id)") }; return t }
}
public enum ToolError: LocalizedError, Sendable {
    case invalid(String), unavailable(String), denied(String)
    public var errorDescription: String? { switch self { case .invalid(let s), .unavailable(let s), .denied(let s): s } }
}
public func textProperty(_ description: String, choices: [String]? = nil) -> JSONValue {
    var p: [String: JSONValue] = ["type": .string("string"), "description": .string(description)]
    if let choices { p["enum"] = .array(choices.map(JSONValue.string)) }; return .object(p)
}
