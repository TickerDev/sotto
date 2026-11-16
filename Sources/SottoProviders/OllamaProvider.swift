import Foundation
import SottoTools

public enum ReasoningBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI, ollama
    public var id: String { rawValue }
    public var name: String { self == .openAI ? "OpenAI" : "Ollama on this Mac" }
    public var requiresRemoteConsent: Bool { self == .openAI }
}

public struct OllamaEndpoint: Sendable, Equatable {
    public let url: URL
    public init(_ value: String) throws {
        guard var c = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(c.scheme?.lowercased() ?? ""),
              let host = c.host?.lowercased(), ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", c.port == nil || (1...65535).contains(c.port!) else {
            throw ToolError.invalid("Ollama must use a loopback address such as http://127.0.0.1:11434. Remote servers and embedded credentials are not supported.")
        }
        // Avoid DNS/proxy routing of a supposedly local destination.
        if host == "localhost" { c.host = "127.0.0.1" }
        c.path = ""
        guard let url = c.url else { throw ToolError.invalid("Invalid Ollama address") }
        self.url = url
    }
}

public struct OllamaProvider: ReasoningProvider {
    public let endpoint: OllamaEndpoint
    private let model: String
    private let session: URLSession
    public init(endpoint: String = "http://127.0.0.1:11434", model: String) throws {
        self.endpoint = try OllamaEndpoint(endpoint); self.model = model
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 300
        config.connectionProxyDictionary = [:]; config.httpShouldSetCookies = false; config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    private func request(_ path: String, body: JSONValue? = nil) throws -> URLRequest {
        var request = URLRequest(url: endpoint.url.appendingPathComponent("api/\(path)"))
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ToolError.unavailable("Invalid Ollama response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw ToolError.unavailable("Ollama model or API not found. Refresh models in Intelligence → Advanced.") }
            throw ToolError.unavailable("Ollama request failed (HTTP \(http.statusCode)). Check its server and selected model.")
        }
    }
    private func json(_ request: URLRequest) async throws -> JSONValue {
        let (bytes, response) = try await session.bytes(for: request); try check(response)
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_097_152 else { throw ToolError.unavailable("Ollama metadata exceeded Sotto’s size limit") }
            data.append(byte)
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), value.object != nil else { throw ToolError.unavailable("Ollama returned invalid metadata") }
        return value
    }
    static func isCloud(_ value: JSONValue) -> Bool {
        ["remote_host", "remote_model"].contains { !(value.object?[$0]?.string ?? "").isEmpty }
    }
    static func modelInfo(_ name: String, details: JSONValue) -> ModelInfo {
        if isCloud(details) { return ModelInfo(id: name, supportsTools: false, unavailableReason: "Cloud-backed model · unavailable in local mode") }
        let capabilities: [JSONValue]
        if case .array(let values) = details.object?["capabilities"] { capabilities = values } else { capabilities = [] }
        let tools = capabilities.contains(.string("tools"))
        return ModelInfo(id: name, supportsTools: tools, unavailableReason: tools ? nil : "Tool calling is not advertised by this model")
    }
    public func models() async throws -> [ModelInfo] {
        do {
            let catalog = try await json(request("tags"))
            guard case .array(let values) = catalog.object?["models"], values.count <= 64 else { throw ToolError.unavailable("Invalid or oversized Ollama model catalog (maximum 64 models)") }
            var result: [ModelInfo] = []
            var seen = Set<String>()
            for value in values {
                try Task.checkCancellation()
                guard let name = value.object?["name"]?.string, !name.isEmpty, name.count <= 256, seen.insert(name).inserted else { throw ToolError.unavailable("Ollama returned an invalid model name") }
                if Self.isCloud(value) { result.append(Self.modelInfo(name, details: value)); continue }
                let details = try await json(request("show", body: .object(["model": .string(name)])))
                result.append(Self.modelInfo(name, details: details))
            }
            return result.sorted { $0.id < $1.id }
        } catch { throw Self.friendly(error) }
    }
    static func friendly(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return CancellationError() }
        if error is URLError { return ToolError.unavailable("Local intelligence is unavailable. Choose Enable local intelligence in Intelligence to let Sotto start it.") }
        return error
    }
    public func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !model.isEmpty else { throw ToolError.unavailable("Choose an installed Ollama model in Intelligence → Advanced.") }
                    // Recheck before sending any transcript: a local tag can be replaced
                    // by a cloud-backed model after its initial discovery.
                    let details = try await json(request("show", body: .object(["model": .string(model)])))
                    let info = Self.modelInfo(model, details: details)
                    guard info.supportsTools else { throw ToolError.unavailable(info.unavailableReason ?? "This local model cannot use tools") }
                    let messages = try OllamaConversation.messages(input, instructions: instructions)
                    let definitions = tools.map { tool in JSONValue.object(["type": .string("function"), "function": .object(["name": .string(tool.id), "description": .string(tool.description), "parameters": tool.inputSchema])]) }
                    let body: [String: JSONValue] = ["model": .string(model), "messages": .array(messages), "tools": .array(definitions), "stream": .bool(true), "keep_alive": .string("1m"), "options": .object(["num_ctx": .number(8192), "num_predict": .number(2048), "temperature": .number(0)])]
                    let (bytes, response) = try await session.bytes(for: request("chat", body: .object(body))); try check(response)
                    var decoder = OllamaStreamDecoder()
                    var line = Data(), total = 0
                    for try await byte in bytes {
                        try Task.checkCancellation(); total += 1
                        guard total <= 8_388_608, line.count < 262_144 else { throw ToolError.unavailable("Ollama output exceeded Sotto’s size limit") }
                        if byte == 10 {
                            if !line.isEmpty {
                                let text = try decoder.consume(line)
                                if !text.isEmpty { continuation.yield(.text(text)) }
                                line.removeAll(keepingCapacity: true)
                                if decoder.done { break }
                            }
                        } else { line.append(byte) }
                    }
                    if !line.isEmpty && !decoder.done {
                        let text = try decoder.consume(line); if !text.isEmpty { continuation.yield(.text(text)) }
                    }
                    guard decoder.done else { throw ToolError.unavailable("Ollama disconnected before completing its response") }
                    continuation.yield(.output(try decoder.output())); continuation.finish()
                } catch { continuation.finish(throwing: Self.friendly(error)) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
