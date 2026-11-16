import Foundation
import SottoTools

public struct ModelInfo: Sendable, Identifiable {
    public let id: String
    public let supportsTools: Bool
    public let unavailableReason: String?
    public init(id: String, supportsTools: Bool, unavailableReason: String? = nil) { self.id = id; self.supportsTools = supportsTools; self.unavailableReason = unavailableReason }
}
public enum ProviderEvent: Sendable { case text(String), output([JSONValue]) }
public protocol ReasoningProvider: Sendable {
    func models() async throws -> [ModelInfo]
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error>
}
public struct ToolCall: Sendable {
    public let id: String; public let name: String; public let arguments: JSONValue
    public init?(item: JSONValue) throws {
        guard let obj = item.object, obj["type"]?.string == "function_call" else { return nil }
        guard let id = obj["call_id"]?.string, let name = obj["name"]?.string, let arguments = obj["arguments"]?.string, let data = arguments.data(using: .utf8) else { throw ToolError.invalid("Malformed tool call") }
        self.id = id; self.name = name
        do { self.arguments = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw IntelligenceResponseError.invalidAction }
        guard self.arguments.object != nil else { throw IntelligenceResponseError.invalidAction }
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct OpenAIProvider: ReasoningProvider {
    private let key: String
    private let model: String
    private let session: URLSession
    public init(key: String, model: String) {
        self.key = key; self.model = model
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    public static func supportsTools(_ id: String) -> Bool {
        ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4o", "gpt-4o-mini"].contains(id)
    }
    private func request(_ path: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!)
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); return r
    }
    public func models() async throws -> [ModelInfo] {
        let (data, response) = try await session.data(for: request("models"))
        try Self.check(response)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .array(let models) = value.object?["data"] else { throw ToolError.unavailable("Invalid model catalog") }
        return models.compactMap { $0.object?["id"]?.string }.sorted().map { ModelInfo(id: $0, supportsTools: Self.supportsTools($0)) }
    }
    public static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ToolError.unavailable("Invalid provider response") }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw ToolError.denied("Provider authentication failed. Check the API key in Settings.")
        case 429: throw ToolError.unavailable("Provider rate or billing limit reached. Try again later.")
        default: throw ToolError.unavailable("Provider request failed (HTTP \(http.statusCode)).")
        }
    }
    public func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard Self.supportsTools(model) else { throw ToolError.unavailable("This model is not verified for tool calling in Sotto. Choose a supported model.") }
                    var r = request("responses"); r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let definitions: [JSONValue] = tools.map { .object(["type": .string("function"), "name": .string($0.id), "description": .string($0.description), "parameters": $0.inputSchema, "strict": .bool(true)]) }
                    r.httpBody = try JSONEncoder().encode(JSONValue.object(["model": .string(model), "input": .array(input), "instructions": .string(instructions), "tools": .array(definitions), "stream": .bool(true), "store": .bool(false), "parallel_tool_calls": .bool(false), "max_output_tokens": .number(2048)]))
                    let (bytes, response) = try await session.bytes(for: r); try Self.check(response)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: "), let data = String(line.dropFirst(6)).data(using: .utf8), let event = try? JSONDecoder().decode(JSONValue.self, from: data), let obj = event.object else { continue }
                        switch obj["type"]?.string {
                        case "response.output_text.delta": if let text = obj["delta"]?.string { continuation.yield(.text(text)) }
                        case "response.completed":
                            guard case .array(let output) = obj["response"]?.object?["output"] else { throw ToolError.unavailable("Provider returned no output") }
                            continuation.yield(.output(output)); continuation.finish(); return
                        case "error", "response.failed", "response.incomplete": throw ToolError.unavailable("Provider could not finish this request. Try again.")
                        default: break
                        }
                    }
                    throw ToolError.unavailable("Provider disconnected before completing the response.")
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
