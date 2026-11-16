import Foundation
import SottoTools

enum OllamaConversation {
    static func messages(_ input: [JSONValue], instructions: String) throws -> [JSONValue] {
        var messages: [JSONValue] = [.object(["role": .string("system"), "content": .string(instructions)])]
        var names: [String: String] = [:]
        for item in input {
            guard let object = item.object else { throw ToolError.invalid("Invalid conversation item") }
            switch object["type"]?.string {
            case "function_call":
                guard let call = try ToolCall(item: item), call.arguments.object != nil else { throw ToolError.invalid("Invalid tool-call arguments") }
                names[call.id] = call.name
                let tool: JSONValue = .object(["id": .string(call.id), "function": .object(["name": .string(call.name), "arguments": call.arguments])])
                if messages.last?.object?["role"]?.string != "assistant" { messages.append(.object(["role": .string("assistant"), "content": .string("")])) }
                var message = messages.removeLast().object!
                var calls: [JSONValue] = []; if case .array(let values) = message["tool_calls"] { calls = values }
                calls.append(tool); message["tool_calls"] = .array(calls); messages.append(.object(message))
            case "function_call_output":
                guard let id = object["call_id"]?.string, let name = names[id], let output = object["output"]?.string else { throw ToolError.invalid("Tool result has no matching call") }
                messages.append(.object(["role": .string("tool"), "tool_name": .string(name), "tool_call_id": .string(id), "content": .string(output)]))
            case nil, "message":
                guard let role = object["role"]?.string, ["user", "assistant"].contains(role) else { throw ToolError.invalid("Unsupported conversation role") }
                let content: String
                if let text = object["content"]?.string { content = text }
                else if case .array(let parts) = object["content"] { content = parts.compactMap { $0.object?["text"]?.string }.joined() }
                else { throw ToolError.invalid("Unsupported conversation content") }
                var message: [String: JSONValue] = ["role": .string(role), "content": .string(content)]
                if role == "assistant", let thinking = object["sotto_ollama_thinking"]?.string { message["thinking"] = .string(thinking) }
                messages.append(.object(message))
            default: throw ToolError.invalid("Unsupported conversation item")
            }
        }
        return messages
    }
}

struct OllamaStreamDecoder {
    private(set) var done = false
    private var content = "", thinking = ""
    private var calls: [JSONValue] = []
    private var indices = Set<Double>()
    mutating func consume(_ data: Data) throws -> String {
        guard !done, let chunk = try? JSONDecoder().decode(JSONValue.self, from: data), let object = chunk.object else { throw ToolError.unavailable("Ollama returned malformed streaming data") }
        guard object["error"] == nil, !OllamaProvider.isCloud(chunk) else { throw ToolError.unavailable("Ollama returned an error or a cloud-backed response; local execution stopped") }
        var delta = ""
        if let message = object["message"]?.object {
            guard message["role"] == nil || message["role"]?.string == "assistant" else { throw ToolError.invalid("Unexpected local model response role") }
            delta = message["content"]?.string ?? ""; content += delta
            thinking += message["thinking"]?.string ?? ""
            guard content.utf8.count <= 131_072, thinking.utf8.count <= 262_144 else { throw ToolError.unavailable("Local model response is too long") }
            if case .array(let values) = message["tool_calls"] {
                for value in values {
                    guard let function = value.object?["function"]?.object,
                          let name = function["name"]?.string, !name.isEmpty, name.count <= 128,
                          let arguments = function["arguments"], arguments.object != nil, arguments.encoded.utf8.count <= 32768, calls.count < 16 else { throw ToolError.invalid("Malformed Ollama tool call") }
                    if case .number(let index) = function["index"] {
                        guard index >= 0, index < 16, index.rounded() == index, indices.insert(index).inserted else { throw ToolError.invalid("Duplicate or fragmented Ollama tool call") }
                    }
                    calls.append(.object(["type": .string("function_call"), "call_id": .string(UUID().uuidString), "name": .string(name), "arguments": .string(arguments.encoded)]))
                }
            }
        }
        if object["done"] == .bool(true) {
            guard object["done_reason"]?.string != "length" else { throw ToolError.unavailable("The local model reached its response limit; no actions were executed") }
            done = true
        }
        return delta
    }
    func output() throws -> [JSONValue] {
        guard done, !content.isEmpty || !calls.isEmpty else { throw ToolError.unavailable("Local model returned no answer or tool call") }
        var message: [String: JSONValue] = ["type": .string("message"), "role": .string("assistant"), "content": .array([.object(["type": .string("output_text"), "text": .string(content)])])]
        if !thinking.isEmpty { message["sotto_ollama_thinking"] = .string(thinking) }
        return [.object(message)] + calls
    }
}
