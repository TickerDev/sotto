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
    public var encoded: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "null" }
}
public enum Risk: String, Sendable { case read, reversible, consequential }
public enum Capability: String, Sendable { case files, applications, automation, reminders, calendar }
public struct ToolDescriptor: Sendable {
    public let id: String
    public let description: String
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue
    public let risk: Risk
    public let capabilities: [Capability]
    public init(id: String, description: String, properties: [String: JSONValue], required: [String], risk: Risk, capabilities: [Capability]) {
        self.id = id; self.description = description; self.risk = risk; self.capabilities = capabilities
        inputSchema = .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)])
        outputSchema = .object(["type": .string("object"), "properties": .object(["summary": .object(["type": .string("string")]), "data": .object([:])])])
    }
    public func validate(_ arguments: JSONValue) throws {
        guard let object = arguments.object, let schema = inputSchema.object,
              let properties = schema["properties"]?.object else { throw ToolError.invalid("Expected an object") }
        let required: [JSONValue]
        if case .array(let values) = schema["required"] { required = values } else { required = [] }
        for key in required.compactMap(\.string) where object[key] == nil { throw ToolError.invalid("Missing \(key)") }
        for (key, value) in object {
            guard let definition = properties[key]?.object else { throw ToolError.invalid("Unknown parameter \(key)") }
            if definition["type"]?.string == "string", value.string == nil { throw ToolError.invalid("\(key) must be text") }
            if case .array(let choices) = definition["enum"], !choices.contains(value) { throw ToolError.invalid("Invalid \(key)") }
            if let text = value.string, text.count > 4096 { throw ToolError.invalid("Parameter too long") }
        }
    }
}
public struct ToolResult: Codable, Sendable, Equatable {
    public let summary: String
    public let data: JSONValue
    public init(_ summary: String, data: JSONValue = .null) { self.summary = summary; self.data = data }
    public var encoded: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "{}" }
}
public protocol Tool: Sendable {
    var descriptor: ToolDescriptor { get }
    func execute(arguments: JSONValue) async throws -> ToolResult
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
