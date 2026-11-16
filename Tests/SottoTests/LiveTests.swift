import XCTest
import SottoTools
import SottoProviders
import SottoSecurity
import SottoAgent
import SottoIntegrations

private actor LiveEvidence {
    var results: [ToolResult] = []
    var failures: [String] = []
    var questions: [String] = []
    func record(_ event: AgentEvent) { if case .question(let question) = event { questions.append(question) }; if case .result(_, let result) = event { results.append(result) }; if case .failure(_, let error) = event { failures.append(error) } }
}
final class LiveTests: XCTestCase, @unchecked Sendable {
    func testLiveClarification() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in: uses a real API key; no native action tools exposed") }
        let key = try XCTUnwrap(KeychainStore.read(), "No Sotto API key")
        let provider = OpenAIProvider(key: key, model: "gpt-4.1-mini")
        let runtime = AgentRuntime(registry: ToolRegistry([]), gate: AuthorizationGate())
        let evidence = LiveEvidence()
        let context = try await runtime.run("Remind me to review my notes. I haven't specified when; ask me what date and time before doing anything.", provider: provider) { await evidence.record($0) }
        let questions = await evidence.questions; let results = await evidence.results; let failures = await evidence.failures
        XCTAssertEqual(questions.count, 1); XCTAssertTrue(results.isEmpty); XCTAssertTrue(failures.isEmpty)
        _ = try await runtime.run("Cancel that request.", context: context, provider: provider) { await evidence.record($0) }
        let finalQuestions = await evidence.questions
        XCTAssertEqual(finalQuestions.count, 1, "Cancellation should not ask another question")
    }
    func testLiveOpenDownloads() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in: opens Downloads and uses a real API key from Keychain") }
        let key = try XCTUnwrap(KeychainStore.read(), "No Sotto API key")
        let tool = try NativeTools.registry().tool("open_folder")
        let runtime = AgentRuntime(registry: ToolRegistry([tool]), gate: AuthorizationGate()); let evidence = LiveEvidence()
        _ = try await runtime.run("Open my Downloads folder", provider: OpenAIProvider(key: key, model: "gpt-4.1-mini")) { await evidence.record($0) }
        let results = await evidence.results; let failures = await evidence.failures
        XCTAssertFalse(results.isEmpty, "No actual tool result"); XCTAssertTrue(failures.isEmpty, "Native tool failed")
    }
}
