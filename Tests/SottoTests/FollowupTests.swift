import XCTest
@testable import SottoAgent
@testable import SottoUI
import SottoTools
import SottoProviders
import SottoSecurity

private actor FollowupProbe {
    var executions = 0
    var questions: [String] = []
    var results: [ToolResult] = []
    func execute() { executions += 1 }
    func receive(_ event: AgentEvent) {
        if case .question(let text) = event { questions.append(text) }
        if case .result(_, let result) = event { results.append(result) }
    }
}
private struct FollowupAction: Tool {
    let probe: FollowupProbe
    let descriptor = ToolDescriptor(id: "followup_action", description: "Test native action", properties: [:], required: [], risk: .reversible, capabilities: [])
    func execute(arguments: JSONValue) async throws -> ToolResult { await probe.execute(); return ToolResult("Confirmed test action") }
}
private struct FollowupProvider: ReasoningProvider {
    func models() async throws -> [ModelInfo] { [] }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { c in
            let finishedCalls = input.compactMap { item -> String? in
                item.object?["type"]?.string == "function_call_output" ? item.object?["call_id"]?.string : nil
            }
            if finishedCalls.contains("action") {
                c.yield(.text("Done"))
                c.yield(.output([.object(["type": .string("message"), "role": .string("assistant"), "content": .array([.object(["type": .string("output_text"), "text": .string("Done")])])])]))
            } else {
                let needsQuestion = !finishedCalls.contains("question")
                c.yield(.output([.object([
                    "type": .string("function_call"), "call_id": .string(needsQuestion ? "question" : "action"),
                    "name": .string(needsQuestion ? "ask_user" : "followup_action"),
                    "arguments": .string(needsQuestion ? "{\"question\":\"What time tomorrow?\"}" : "{}")
                ])]))
            }
            c.finish()
        }
    }
}
private actor MemoryCredentials: CredentialStorage {
    func containsKey() -> Bool { true }
    func read() -> String? { "fixture-key" }
    func save(_ key: String) throws {}
}
private actor PillBoundaryRecorder {
    struct Call: Sendable {
        let userMessages: [String]
        let toolIDs: [String]
        let recalledOutputs: [String]
    }
    var calls: [Call] = []
    func record(input: [JSONValue], tools: [ToolDescriptor]) {
        let users = input.filter { $0.object?["role"]?.string == "user" }.compactMap { $0.object?["content"]?.string }
        let recalled = input.filter { $0.object?["type"]?.string == "function_call_output" }.compactMap { $0.object?["output"]?.string }
        calls.append(Call(userMessages: users, toolIDs: tools.map(\.id), recalledOutputs: recalled))
    }
}
private struct PillBoundaryProvider: ReasoningProvider {
    let recorder: PillBoundaryRecorder
    let onReply: @Sendable () -> Void
    func models() async throws -> [ModelInfo] { [ModelInfo(id: "gpt-4.1-mini", supportsTools: true)] }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                await recorder.record(input: input, tools: tools)
                let latestUser = input.last(where: { $0.object?["role"]?.string == "user" })?.object?["content"]?.string ?? ""
                let recalled = input.filter { $0.object?["type"]?.string == "function_call_output" }.compactMap { $0.object?["output"]?.string }
                if latestUser == "What did I ask earlier?" && recalled.isEmpty {
                    c.yield(.output([.object([
                        "type": .string("function_call"), "call_id": .string("recall-1"),
                        "name": .string(PreviousConversationTool.id), "arguments": .string("{}")
                    ])]))
                } else {
                    let replyText = recalled.isEmpty ? "Reply to: \(latestUser)" : "Earlier you asked: \(recalled.joined(separator: " "))"
                    c.yield(.text(replyText))
                    c.yield(.output([.object(["role": .string("assistant"), "content": .string(replyText)])]))
                    onReply()
                }
                c.finish()
            }
            c.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
final class FollowupTests: XCTestCase, @unchecked Sendable {
    func testQuestionPausesWithoutSuccessAndReplyResumesOriginalRequest() async throws {
        let probe = FollowupProbe()
        let runtime = AgentRuntime(registry: ToolRegistry([FollowupAction(probe: probe)]), gate: AuthorizationGate())
        let first = try await runtime.run("Review my notes tomorrow", provider: FollowupProvider()) { await probe.receive($0) }
        let before = await probe.executions; let questions = await probe.questions; let results = await probe.results
        XCTAssertEqual(before, 0); XCTAssertEqual(questions, ["What time tomorrow?"]); XCTAssertTrue(results.isEmpty)
        // A completed call/output pair is preserved before the user's next message.
        XCTAssertTrue(first.contains { $0.object?["call_id"]?.string == "question" && $0.object?["type"]?.string == "function_call_output" })
        let second = try await runtime.run("5 PM", context: first, provider: FollowupProvider()) { await probe.receive($0) }
        let after = await probe.executions
        XCTAssertEqual(after, 1)
        XCTAssertEqual(second.filter { $0.object?["role"]?.string == "user" }.compactMap { $0.object?["content"]?.string }, ["Review my notes tomorrow", "5 PM"])
    }
    func testBlankQuestionIsRejected() async throws {
        do { _ = try await ClarificationTool().execute(arguments: .object(["question": .string("  \n")])); XCTFail("Blank question accepted") }
        catch is ToolError {}
    }
    func testQuestionAndInformationalStatesDoNotMasqueradeAsCompletion() {
        var machine = AgentStateMachine()
        XCTAssertTrue(machine.transition(to: .thinking)); XCTAssertTrue(machine.transition(to: .awaitingInput))
        XCTAssertFalse(machine.transition(to: .completed))
        XCTAssertTrue(machine.transition(to: .listening)); XCTAssertTrue(machine.transition(to: .transcribing))
        XCTAssertTrue(machine.transition(to: .thinking)); XCTAssertTrue(machine.transition(to: .responded))
        XCTAssertTrue(machine.transition(to: .listening)); XCTAssertTrue(machine.transition(to: .idle))
    }
    func testApprovalShowsReadableValuesWithoutChangingAuthorization() {
        let args: JSONValue = .object(["path": .string("~/Downloads/My report.pdf"), "action": .string("open")])
        let approval = Approval(tool: "open_file", arguments: args)
        let presentation = ApprovalPresentation(approval)
        XCTAssertEqual(presentation.title, "Open file")
        XCTAssertEqual(presentation.fields.map(\.label), ["File", "Location"])
        XCTAssertEqual(presentation.fields.map(\.value), ["My report.pdf", "~/Downloads/My report.pdf"])
        XCTAssertEqual(approval.arguments, args)
        XCTAssertEqual(ApprovalPresentation(Approval(tool: "open_file", arguments: .object(["path": .string("/tmp/report.pdf"), "action": .string("reveal")]))).title, "Reveal file in Finder")
    }
    func testPreviousConversationToolFormatsMostRecentFirstAndClipsSafely() async throws {
        let older: [JSONValue] = [
            .object(["role": .string("user"), "content": .string("Search the web for Swift")]),
            .object(["role": .string("assistant"), "content": .string("I can't search the web.")])
        ]
        let newer: [JSONValue] = [
            .object(["role": .string("user"), "content": .string("Find my resume")]),
            .object(["type": .string("function_call"), "call_id": .string("c1"), "name": .string("find_files"), "arguments": .string("{\"name\":\"resume\"}")]),
            .object(["type": .string("function_call_output"), "call_id": .string("c1"), "output": .string(ToolResult("Found 1 matching file.", data: .string("/Users/test/Resume.pdf")).encoded)]),
            .object(["role": .string("assistant"), "content": .string("I found Resume.pdf.")])
        ]
        let result = try await PreviousConversationTool(conversations: [older, newer]).execute(arguments: .object([:]))
        let text = try XCTUnwrap(result.data.string)
        XCTAssertTrue(text.contains("Most recent ended conversation:"))
        XCTAssertTrue(text.contains("Find my resume"))
        XCTAssertTrue(text.contains("Resume.pdf"))
        XCTAssertTrue(text.contains("Earlier ended conversation 2:"))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "Most recent ended conversation:")?.lowerBound),
                          try XCTUnwrap(text.range(of: "Earlier ended conversation 2:")?.lowerBound))
    }
    @MainActor func testClosingPillEndsConversationAndExposesRecallToolToModel() async throws {
        @MainActor final class ExpectationBox {
            var current: XCTestExpectation?
        }
        let recorder = PillBoundaryRecorder()
        let box = ExpectationBox()
        let connection = ProviderConnection(credentials: MemoryCredentials()) { _, _ in
            PillBoundaryProvider(recorder: recorder) { Task { @MainActor in box.current?.fulfill() } }
        }
        var prefs = Preferences()
        prefs.automaticIntelligence = false
        prefs.reasoningBackend = .openAI
        prefs.remoteConsent = true
        prefs.model = "gpt-4.1-mini"
        let app = AppModel(providerConnection: connection, preferences: prefs, startServices: false, onDeviceAvailable: { false })

        // Turn 1: initial request with no prior ended conversation.
        let turn1 = expectation(description: "Turn 1")
        box.current = turn1
        app.submit("Search the web for Swift")
        await fulfillment(of: [turn1], timeout: 2)
        for _ in 0..<40 where app.state == .thinking || app.state == .executing {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(app.state, .responded)
        XCTAssertNotNil(app.autoDismissWindow)

        // Turn 2 while the pill is still open continues the active conversation directly.
        let turn2 = expectation(description: "Turn 2 while pill open")
        box.current = turn2
        app.submit("Why not?")
        await fulfillment(of: [turn2], timeout: 2)
        for _ in 0..<40 where app.state == .thinking || app.state == .executing {
            try? await Task.sleep(for: .milliseconds(20))
        }

        // Close the pill: active conversation ends and is archived, and auto-dismiss ring clears.
        app.cancel()
        XCTAssertNil(app.autoDismissWindow)

        // Turn 3 after closing the pill starts fresh without the old conversation in `input`,
        // while exposing `recall_previous_conversation` if the model decides to refer back.
        let turn3 = expectation(description: "Turn 3 after pill closed")
        box.current = turn3
        app.submit("Open Google Chrome")
        await fulfillment(of: [turn3], timeout: 2)
        try? await Task.sleep(for: .milliseconds(20))

        // Close the pill again, then ask something that triggers recall_previous_conversation.
        app.cancel()
        let turn4 = expectation(description: "Turn 4 recalls previous conversation")
        box.current = turn4
        app.submit("What did I ask earlier?")
        await fulfillment(of: [turn4], timeout: 2)
        try? await Task.sleep(for: .milliseconds(20))

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 5)
        XCTAssertEqual(calls[0].userMessages, ["Search the web for Swift"])
        XCTAssertFalse(calls[0].toolIDs.contains(PreviousConversationTool.id))
        XCTAssertEqual(calls[1].userMessages, ["Search the web for Swift", "Why not?"])
        XCTAssertFalse(calls[1].toolIDs.contains(PreviousConversationTool.id))
        XCTAssertEqual(calls[2].userMessages, ["Open Google Chrome"])
        XCTAssertTrue(calls[2].toolIDs.contains(PreviousConversationTool.id))
        XCTAssertEqual(calls[3].userMessages, ["What did I ask earlier?"])
        XCTAssertTrue(calls[3].recalledOutputs.isEmpty)
        XCTAssertEqual(calls[4].userMessages, ["What did I ask earlier?"])
        XCTAssertTrue(calls[4].recalledOutputs.first?.contains("Open Google Chrome") == true)
        XCTAssertTrue(calls[4].recalledOutputs.first?.contains("Search the web for Swift") == true)
        XCTAssertEqual(app.state, .responded)
        XCTAssertTrue(app.confirmedSummary.isEmpty)
        XCTAssertTrue(app.activities.isEmpty)
        app.shutdown()
    }
}
