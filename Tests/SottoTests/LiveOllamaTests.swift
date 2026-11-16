import XCTest
import SottoProviders
import SottoAgent
import SottoSecurity
import SottoIntegrations
import SottoTools

private actor LocalLiveEvidence {
    var results: [ToolResult] = []
    var failures: [String] = []
    func receive(_ event: AgentEvent) {
        if case .result(_, let result) = event { results.append(result) }
        if case .failure(_, let error) = event { failures.append(error) }
    }
}
final class LiveOllamaTests: XCTestCase, @unchecked Sendable {
    func provider() throws -> OllamaProvider {
        guard ProcessInfo.processInfo.environment["SOTTO_OLLAMA_TESTS"] == "1" else { throw XCTSkip("Opt-in: requires a running local Ollama server and installed tool-capable model") }
        return try OllamaProvider(model: ProcessInfo.processInfo.environment["SOTTO_OLLAMA_MODEL"] ?? "qwen3:1.7b")
    }
    func testLiveLocalModelOpensDownloadsAndConsumesActualResult() async throws {
        let provider = try provider()
        let catalog = try await provider.models()
        XCTAssertTrue(catalog.contains { $0.id == (ProcessInfo.processInfo.environment["SOTTO_OLLAMA_MODEL"] ?? "qwen3:1.7b") && $0.supportsTools })
        let runtime = AgentRuntime(registry: ToolRegistry([try NativeTools.registry().tool("open_folder")]), gate: AuthorizationGate())
        let evidence = LocalLiveEvidence()
        let history = try await runtime.run("Open my Downloads folder", provider: provider) { await evidence.receive($0) }
        let results = await evidence.results, failures = await evidence.failures
        XCTAssertEqual(results.count, 1, "A local model must request the actual native action")
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
        XCTAssertTrue(results.first?.summary.contains("Downloads") == true)
        XCTAssertTrue(history.contains { $0.object?["type"]?.string == "function_call_output" })
        XCTAssertEqual(history.last?.object?["type"], .string("message"), "Model must consume the result and finish its turn")
    }
    func testLiveLocalRequestCanBeCancelled() async throws {
        let provider = try provider()
        let task = Task {
            for try await _ in provider.stream(input: [.object(["role": .string("user"), "content": .string("Count from one to one hundred thousand, one number at a time.")])], tools: [], instructions: "Follow the user instruction.") {}
        }
        try await Task.sleep(for: .milliseconds(150))
        let cancelledAt = ContinuousClock.now
        task.cancel()
        // AsyncThrowingStream may finish with nil when its consumer is canceled;
        // either graceful termination or CancellationError is valid.
        do { try await task.value }
        catch is CancellationError {} catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertTrue(task.isCancelled)
        XCTAssertLessThan(cancelledAt.duration(to: .now), .seconds(2))
    }
}
