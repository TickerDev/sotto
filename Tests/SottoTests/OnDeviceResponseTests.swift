import XCTest
import Foundation
import SottoTools
import SottoAgent
import SottoSecurity
import SottoIntegrations
@testable import SottoProviders
#if canImport(FoundationModels)
import FoundationModels
#endif

private actor CompoundActionProbe {
    var calls: [String] = []
    func record(_ name: String) { calls.append(name) }
}
private struct CompoundProbeTool: SottoTools.Tool {
    let descriptor: ToolDescriptor
    let probe: CompoundActionProbe
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        if descriptor.id == "open_folder", arguments.object?["path"]?.string == "~/Downloads" {
            await probe.record(descriptor.id)
            return ToolResult("Opened Downloads in Finder")
        }
        if descriptor.id == "spotify", arguments.object?["action"]?.string == "play" {
            await probe.record(descriptor.id)
            return ToolResult("Playing · Fixture track")
        }
        if descriptor.id == "applications" {
            let action = arguments.object?["action"]?.string ?? ""
            if action == "list" {
                await probe.record("applications:list")
                return ToolResult("Running applications", data: .array([.object(["name": .string("Google Chrome"), "bundle_id": .string("com.google.Chrome")])]))
            }
            if action == "open" {
                let bundleID = arguments.object?["bundle_id"]?.string ?? ""
                await probe.record("applications:open:\(bundleID)")
                return ToolResult("Opened Google Chrome")
            }
        }
        throw ToolError.invalid("The test request only authorizes fixture tools")
    }
}
final class OnDeviceResponseTests: XCTestCase, @unchecked Sendable {
    let folder = ToolDescriptor(id: "open_folder", description: "Open folder", properties: ["path": textProperty("Path")], required: ["path"], risk: .reversible, capabilities: [.files])
    func testMalformedProviderArgumentsHaveActionableContentFreeError() {
        for value in ["not json", "{\"path\":", "[]", "null", "\"a string\""] {
            let item: JSONValue = .object(["type": .string("function_call"), "call_id": .string("test"), "name": .string("open_folder"), "arguments": .string(value)])
            XCTAssertThrowsError(try ToolCall(item: item)) { error in
                XCTAssertTrue(error is IntelligenceResponseError)
                XCTAssertTrue(error.localizedDescription.contains("Intelligence"))
                XCTAssertFalse(error.localizedDescription.contains(value))
            }
        }
    }
    func testReportedCompoundRequestRunsNativelyWithoutIntelligence() async throws {
        let probe = CompoundActionProbe()
        let registry = ToolRegistry(NativeTools.registry().descriptors.map { CompoundProbeTool(descriptor: $0, probe: probe) })
        let runtime = AgentRuntime(registry: registry, gate: AuthorizationGate())
        let command = "open downloads folder and resume music on Spotify"
        let provider = try XCTUnwrap(NativeCommandProvider(command: command))
        _ = try await runtime.run(command, provider: provider) { _ in }
        let calls = await probe.calls
        XCTAssertEqual(calls, ["open_folder", "spotify"])
        XCTAssertNil(NativeCommandProvider(command: "open downloads and delete my files"))
        XCTAssertNil(NativeCommandProvider(command: "resume spotify and send my files"))
    }
    func testFailedFirstNativeActionStopsTheRemainingCompoundRequest() async throws {
        let provider = try XCTUnwrap(NativeCommandProvider(command: "open downloads folder and resume music on Spotify"))
        let failure: JSONValue = .object(["type": .string("function_call_output"), "call_id": .string("first"), "output": .string("Tool failed: access denied")])
        var output: [JSONValue] = []
        for try await event in provider.stream(input: [failure], tools: [], instructions: "") {
            if case .output(let items) = event { output = items }
        }
        XCTAssertFalse(output.contains { $0.object?["type"]?.string == "function_call" })
        XCTAssertTrue(output.first?.object?["content"]?.string?.contains("stopped") == true)
    }
    #if canImport(FoundationModels)
    func testStructuredArgumentsPreserveQuotesUnicodeAndNewlinesWithoutParsingText() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
        let path = "/Users/test/Recipe “book”/a\\b\nfile.pdf"
        let action = LocalAction(tool: "open_folder", arguments: [LocalArgument(name: "path", value: path)], reply: "")
        let call = try XCTUnwrap(ToolCall(item: XCTUnwrap(action.output(tools: [folder]).first)))
        XCTAssertEqual(call.arguments, .object(["path": .string(path)]))
        XCTAssertEqual(call.name, "open_folder")
    }
    func testInvalidStructuredArgumentsAreRejectedBeforeToolExecution() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
        let invalid = [
            LocalAction(tool: "open_folder", arguments: [], reply: ""),
            LocalAction(tool: "open_folder", arguments: [LocalArgument(name: "path", value: "~/Downloads"), LocalArgument(name: "path", value: "~/Documents")], reply: ""),
            LocalAction(tool: "open_folder", arguments: [LocalArgument(name: "unknown", value: "private value")], reply: ""),
            LocalAction(tool: "unknown_tool", arguments: [], reply: ""),
            LocalAction(tool: "", arguments: [], reply: "")
        ]
        for action in invalid {
            XCTAssertThrowsError(try action.output(tools: [folder])) { error in
                XCTAssertTrue(error is IntelligenceResponseError)
                XCTAssertFalse(error.localizedDescription.contains("private value"))
            }
        }
    }
    func testCompletedOnDeviceActionCannotExecuteAgain() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
        let action = LocalAction(tool: "open_folder", arguments: [LocalArgument(name: "path", value: "~/Downloads")], reply: "")
        let call = try XCTUnwrap(action.output(tools: [folder]).first)
        let id = try XCTUnwrap(call.object?["call_id"]?.string)
        let success: JSONValue = .object(["type": .string("function_call_output"), "call_id": .string(id), "output": .string(ToolResult("Opened Downloads in Finder").encoded)])
        XCTAssertTrue(try LocalAction.repeated(action, input: [call, success], tools: [folder]))
        let failure: JSONValue = .object(["type": .string("function_call_output"), "call_id": .string(id), "output": .string("Tool failed")])
        XCTAssertFalse(try LocalAction.repeated(action, input: [call, failure], tools: [folder]))
        let other = LocalAction(tool: "open_folder", arguments: [LocalArgument(name: "path", value: "~/Documents")], reply: "")
        XCTAssertFalse(try LocalAction.repeated(other, input: [call, success], tools: [folder]))
    }
    func testReplyAndParameterlessToolsNeedNoJSONParsing() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
        let reply = LocalAction(tool: "", arguments: [], reply: "How can I help?")
        XCTAssertEqual(try reply.output(tools: []).first?.object?["content"]?.string, "How can I help?")
        let descriptor = ToolDescriptor(id: "list_reminders", description: "List reminders", properties: [:], required: [], risk: .read, capabilities: [.reminders])
        let action = LocalAction(tool: "list_reminders", arguments: [], reply: "")
        let call = try XCTUnwrap(ToolCall(item: XCTUnwrap(action.output(tools: [descriptor]).first)))
        XCTAssertEqual(call.arguments, .object([:]))
    }
    func testOnDevicePromptGuidesConversationalReplyInsteadOfNoActionNeeded() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
        let prompt = try LocalAction.prompt(input: [.object(["role": .string("user"), "content": .string("What is 15 times 4?")])])
        XCTAssertTrue(prompt.contains("talk back naturally"))
        XCTAssertFalse(prompt.lowercased().contains("no action needed"))
    }
    func testRepeatedActionCheckIsScopedToCurrentUserTurn() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires Foundation Models") }
        let action = LocalAction(tool: "open_folder", arguments: [LocalArgument(name: "path", value: "~/Downloads")], reply: "")
        let call = try XCTUnwrap(action.output(tools: [folder]).first)
        let id = try XCTUnwrap(call.object?["call_id"]?.string)
        let success: JSONValue = .object(["type": .string("function_call_output"), "call_id": .string(id), "output": .string(ToolResult("Opened Downloads in Finder").encoded)])
        let turn1: [JSONValue] = [.object(["role": .string("user"), "content": .string("Open Downloads")]), call, success]
        XCTAssertTrue(try LocalAction.repeated(action, input: turn1, tools: [folder]))
        let turn2 = turn1 + [
            .object(["role": .string("assistant"), "content": .string("Opened Downloads.")]),
            .object(["role": .string("user"), "content": .string("Open Downloads again")])
        ]
        XCTAssertFalse(try LocalAction.repeated(action, input: turn2, tools: [folder]))
        let prompt = try LocalAction.prompt(input: turn2)
        XCTAssertTrue(prompt.contains("Earlier Sotto: Opened Downloads."))
        XCTAssertTrue(prompt.contains("Actions already completed in this turn; do not repeat:\nNone"))
    }
    func testLiveOnDeviceActionGenerationWithoutExecution() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_ONDEVICE_TEST"] == "1" else { throw XCTSkip("Opt-in: real on-device generation, no action execution") }
        guard #available(macOS 26, *), OnDeviceIntelligence.available else { throw XCTSkip("On-device intelligence unavailable") }
        var output: [JSONValue] = []
        for try await event in OnDeviceProvider().stream(input: [.object(["role": .string("user"), "content": .string("Open my Documents folder")])], tools: [folder], instructions: "Use open_folder for the user's requested folder. Use ~/Documents for Documents. Do not claim execution.") {
            if case .output(let items) = event { output = items }
        }
        let call = try XCTUnwrap(ToolCall(item: XCTUnwrap(output.first)))
        XCTAssertEqual(call.name, "open_folder")
        XCTAssertEqual(call.arguments.object?["path"]?.string, "~/Documents")
    }
    func testLiveOnDeviceConversationalReplyAvoidsRoboticStatusPhrasing() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_ONDEVICE_TEST"] == "1" else { throw XCTSkip("Opt-in: real on-device generation, no action execution") }
        guard #available(macOS 26, *), OnDeviceIntelligence.available else { throw XCTSkip("On-device intelligence unavailable") }
        let runtime = AgentRuntime(registry: ToolRegistry([CompoundProbeTool(descriptor: folder, probe: CompoundActionProbe())]), gate: AuthorizationGate())
        actor Collector {
            var text = ""
            var questions: [String] = []
            func accept(_ event: AgentEvent) {
                if case .text(let s) = event { text += s }
                if case .question(let q) = event { questions.append(q) }
            }
        }
        let collector = Collector()
        _ = try await runtime.run("What is 15 times 4, and can you change the screen color?", provider: OnDeviceProvider()) { await collector.accept($0) }
        let replyText = await collector.text
        let questions = await collector.questions
        let combined = (replyText + " " + questions.joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(combined.isEmpty)
        XCTAssertFalse(combined.lowercased().contains("no action needed"))
        XCTAssertFalse(combined.lowercased().contains("no tool"))
        print("Live on-device conversational reply:", combined)
    }
    func testLiveOnDeviceToolRoundCompletesWithoutRepeatingError() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_ONDEVICE_TEST"] == "1" else { throw XCTSkip("Opt-in: real on-device generation, no real OS execution") }
        guard #available(macOS 26, *), OnDeviceIntelligence.available else { throw XCTSkip("On-device intelligence unavailable") }
        let probe = CompoundActionProbe()
        let runtime = AgentRuntime(registry: ToolRegistry([CompoundProbeTool(descriptor: folder, probe: probe)]), gate: AuthorizationGate())
        actor Collector {
            var text = ""
            var failures: [String] = []
            func accept(_ event: AgentEvent) {
                if case .text(let s) = event { text += s }
                if case .failure(_, let err) = event { failures.append(err) }
            }
        }
        let collector = Collector()
        _ = try await runtime.run("Open my Downloads folder", provider: OnDeviceProvider()) { await collector.accept($0) }
        let calls = await probe.calls
        let failures = await collector.failures
        let text = await collector.text
        XCTAssertEqual(calls, ["open_folder"])
        XCTAssertTrue(failures.isEmpty)
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        print("Live on-device tool wrap-up:", text)
    }
    func testLiveOnDeviceEndedWebSearchDoesNotLeakIntoOpenGoogleChrome() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_ONDEVICE_TEST"] == "1" else { throw XCTSkip("Opt-in: real on-device generation, no real OS execution") }
        guard #available(macOS 26, *), OnDeviceIntelligence.available else { throw XCTSkip("On-device intelligence unavailable") }
        let probe = CompoundActionProbe()
        let registry = ToolRegistry(NativeTools.registry().descriptors.map { CompoundProbeTool(descriptor: $0, probe: probe) })
        let runtime = AgentRuntime(registry: registry, gate: AuthorizationGate())
        let endedWebSearch: [JSONValue] = [
            .object(["role": .string("user"), "content": .string("Search the web for today's weather")]),
            .object(["role": .string("assistant"), "content": .string("I can't search or browse the web. Would you like me to open a local app or check your calendar instead?")])
        ]
        actor Collector {
            var text = ""
            func accept(_ event: AgentEvent) { if case .text(let s) = event { text += s } }
        }
        let collector = Collector()
        _ = try await runtime.run("Open Google Chrome", context: [], previousConversations: [endedWebSearch], provider: OnDeviceProvider()) { await collector.accept($0) }
        let calls = await probe.calls
        let text = await collector.text
        XCTAssertTrue(calls.contains(where: { $0.hasPrefix("applications:") }), "Expected applications tool call, got \(calls), reply: \(text)")
        XCTAssertFalse(text.lowercased().contains("search the web"))
        print("Live on-device Chrome after ended web search:", calls, text)
    }
    func testLiveOnDeviceModelDecidesToRecallPreviousConversationWhenReferredBack() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_ONDEVICE_TEST"] == "1" else { throw XCTSkip("Opt-in: real on-device generation, no real OS execution") }
        guard #available(macOS 26, *), OnDeviceIntelligence.available else { throw XCTSkip("On-device intelligence unavailable") }
        let probe = CompoundActionProbe()
        let registry = ToolRegistry(NativeTools.registry().descriptors.map { CompoundProbeTool(descriptor: $0, probe: probe) })
        let runtime = AgentRuntime(registry: registry, gate: AuthorizationGate())
        let endedFileSearch: [JSONValue] = [
            .object(["role": .string("user"), "content": .string("Find my tax summary")]),
            .object(["role": .string("assistant"), "content": .string("I found Tax_Summary_2025.pdf in your Documents folder.")])
        ]
        actor Collector {
            var text = ""
            func accept(_ event: AgentEvent) { if case .text(let s) = event { text += s } }
        }
        let collector = Collector()
        let context = try await runtime.run("What file did we find in our last conversation?", context: [], previousConversations: [endedFileSearch], provider: OnDeviceProvider()) { await collector.accept($0) }
        let text = await collector.text
        XCTAssertTrue(context.contains { $0.object?["name"]?.string == "recall_previous_conversation" })
        XCTAssertTrue(text.contains("Tax_Summary_2025"), "Expected recalled filename in reply, got: \(text)")
        print("Live on-device recalled reply:", text)
    }
    #endif
}
