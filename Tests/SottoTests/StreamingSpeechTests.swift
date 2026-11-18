import XCTest
import AppKit
@testable import SottoAudio
@testable import SottoAgent
@testable import SottoUI
import SottoTools
import SottoProviders
import SottoSecurity

private actor PreparedProbe {
    var executions = 0
    var generations = 0
    func execute() { executions += 1 }
    func generated() { generations += 1 }
}
private struct PreparedTool: Tool {
    let probe: PreparedProbe
    let descriptor = ToolDescriptor(id: "probe", description: "Probe", properties: [:], required: [], risk: .consequential, capabilities: [])
    func execute(arguments: JSONValue) async throws -> ToolResult { await probe.execute(); return ToolResult("Verified probe result") }
}
private struct PreparedProvider: ReasoningProvider {
    let probe: PreparedProbe
    let propose: Bool
    func models() async throws -> [ModelInfo] { [] }
    func stream(input: [JSONValue], tools: [ToolDescriptor], instructions: String) -> AsyncThrowingStream<ProviderEvent, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                await probe.generated()
                if propose && !input.contains(where: { $0.object?["type"]?.string == "function_call_output" }) {
                    c.yield(.output([.object(["type": .string("function_call"), "call_id": .string("prepared-call"), "name": .string("probe"), "arguments": .string("{}")])]))
                } else {
                    c.yield(.text("Done")); c.yield(.output([.object(["role": .string("assistant"), "content": .string("Done")])]))
                }
                c.finish()
            }
            c.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

final class StreamingSpeechTests: XCTestCase, @unchecked Sendable {
    func testExplicitToggleAndPausePreparationChoicesPersistWithoutRevivingLegacyToggle() throws {
        var settings = Preferences()
        settings.toggleToTalk = true; settings.prepareWhileSpeaking = false
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(restored.toggleToTalk)
        XCTAssertFalse(restored.prepareWhileSpeaking)
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"toggleToTalk":true}"#.utf8))
        XCTAssertFalse(legacy.toggleToTalk)
        XCTAssertTrue(legacy.prepareWhileSpeaking)
    }
    func testRevisedPartialReplacesEarlierWordsAndFinalSegmentsAccumulate() {
        var text = StreamingTranscript()
        text.receive(text: "Open my Doc", start: 0, end: 1, final: false)
        text.receive(text: "Open my Downloads", start: 0, end: 2, final: false)
        XCTAssertEqual(text.snapshot.provisional, "Open my Downloads")
        text.receive(text: "Open my Downloads", start: 0, end: 2, final: true)
        text.receive(text: "folder", start: 2, end: 3, final: false)
        XCTAssertEqual(text.snapshot.text, "Open my Downloads folder")
        XCTAssertEqual(text.snapshot.confirmed, "Open my Downloads")
        text.receive(text: "folder.", start: 2, end: 3, final: true)
        XCTAssertEqual(text.snapshot.confirmed, "Open my Downloads folder.")
        XCTAssertEqual(text.snapshot.provisional, "")
    }
    func testVolatileResultsCannotOverwriteConfirmedSegments() {
        var text = StreamingTranscript()
        text.receive(text: "Keep this", start: 0, end: 2, final: true)
        text.receive(text: "Wrong revision", start: 0, end: 2, final: false)
        XCTAssertEqual(text.snapshot.text, "Keep this")
        text.receive(text: "Invalid", start: .nan, end: 3, final: true)
        XCTAssertEqual(text.snapshot.text, "Keep this")
    }
    func testPreparationHasZeroSideEffectsAndFinalExecutionStillUsesTrustedApproval() async throws {
        let probe = PreparedProbe(), gate = AuthorizationGate()
        let runtime = AgentRuntime(registry: ToolRegistry([PreparedTool(probe: probe)]), gate: gate)
        let provider = PreparedProvider(probe: probe, propose: true)
        let prepared = try await runtime.prepareTurn("Do the probe", provider: provider, providerKey: "fixture")
        let before = await probe.executions
        XCTAssertEqual(before, 0)
        _ = try await runtime.run("Do the probe.", provider: provider, prepared: prepared, providerKey: "fixture", prepare: { _ in }) { event in
            if case .approval(let request) = event {
                let count = await probe.executions
                XCTAssertEqual(count, 0)
                await gate.resolve(request.id, allowed: true)
            }
        }
        let count = await probe.executions, generations = await probe.generations
        XCTAssertEqual(count, 1)
        XCTAssertEqual(generations, 2, "Reuse the prepared first generation; only the result round is new")
    }
    func testChangedFinalRequestCannotExecuteThePreparedAction() async throws {
        let probe = PreparedProbe(), runtime = AgentRuntime(registry: ToolRegistry([PreparedTool(probe: probe)]), gate: AuthorizationGate())
        let prepared = try await runtime.prepareTurn("Do the probe", provider: PreparedProvider(probe: probe, propose: true), providerKey: "fixture")
        _ = try await runtime.run("Do not do the probe", provider: PreparedProvider(probe: probe, propose: false), prepared: prepared, providerKey: "fixture") { _ in }
        let count = await probe.executions
        XCTAssertEqual(count, 0)
        XCTAssertFalse(prepared.matches(text: "Do the probe", context: [.string("different context")], providerKey: "fixture"))
        XCTAssertFalse(prepared.matches(text: "Do the probe", context: [], providerKey: "different provider"))
        let expired = PreparedAgentTurn(text: "Do the probe", context: [], providerKey: "fixture", output: [], created: .now.advanced(by: .seconds(-20)))
        XCTAssertFalse(expired.matches(text: "Do the probe", context: [], providerKey: "fixture"))
    }
    func testStablePauseNeedsBothQuietAudioAndUnchangedWords() {
        var pause = SpeechPauseTracker()
        pause.transcript("Check my calendar", at: 1)
        pause.audio(0.5, at: 1.5)
        XCTAssertNil(pause.deadline)
        pause.audio(0, at: 1.6)
        XCTAssertEqual(pause.deadline!, 2.15, accuracy: 0.001)
        pause.transcript("Check my calendar tomorrow", at: 2)
        XCTAssertEqual(pause.deadline!, 2.65, accuracy: 0.001)
        XCTAssertTrue(pause.audio(0.5, at: 2.1))
        XCTAssertNil(pause.deadline)
    }
    @MainActor func testResumedSpeechInvalidatesPendingPausePreparation() async throws {
        let controller = VoicePreparationController()
        let started = expectation(description: "Draft inference started")
        controller.begin { _ in started.fulfill(); try? await Task.sleep(for: .seconds(5)); return nil }
        controller.transcript("A complex request", at: ProcessInfo.processInfo.systemUptime - 1)
        await fulfillment(of: [started], timeout: 1)
        controller.audio(1)
        XCTAssertNil(controller.take(for: "A complex request"))
        controller.cancel()
    }
    @MainActor func testNativeCommandsNeverStartSpeculativeInference() async throws {
        let controller = VoicePreparationController()
        let unexpected = expectation(description: "No native inference"); unexpected.isInverted = true
        controller.begin { _ in unexpected.fulfill(); return nil }
        controller.transcript("Open my Downloads folder", at: ProcessInfo.processInfo.systemUptime - 1)
        await fulfillment(of: [unexpected], timeout: 0.05)
        XCTAssertNil(controller.take(for: "Open my Downloads folder"))
        controller.cancel()
    }
    func testVoiceLatencyReportsMeasuredIntervalsWithoutInventingMissingPhases() {
        var trace = VoiceLatencyTrace(started: 10)
        trace.record(.microphoneReady, at: 10.2); trace.record(.firstPartial, at: 10.6)
        trace.record(.inputEnded, at: 12); trace.record(.finalTranscript, at: 12.1)
        XCTAssertEqual(trace.milliseconds["activationToMicrophoneReadyMs"]!, 200, accuracy: 0.001)
        XCTAssertEqual(trace.milliseconds["microphoneToFirstPartialMs"]!, 400, accuracy: 0.001)
        XCTAssertEqual(trace.milliseconds["inputEndToFinalMs"]!, 100, accuracy: 0.001)
        XCTAssertNil(trace.milliseconds["activationToVerifiedCompletionMs"])
        XCTAssertNil(trace.milliseconds["inputEndToFirstActionMs"])
        trace.record(.firstAction, at: 12.3); trace.record(.verifiedCompletion, at: 12.8)
        XCTAssertEqual(trace.milliseconds["inputEndToFirstActionMs"]!, 300, accuracy: 0.001)
        XCTAssertEqual(trace.milliseconds["finalTranscriptToFirstActionMs"]!, 200, accuracy: 0.001)
        XCTAssertEqual(trace.milliseconds["inputEndToVerifiedCompletionMs"]!, 800, accuracy: 0.001)
    }
    @MainActor func testToggleShortcutUsesPressesAndIgnoresReleases() throws {
        let shortcut = GlobalShortcut(); shortcut.toggleMode = true
        var presses = 0, releases = 0, handsFree = 0
        shortcut.pressed = { presses += 1; return true }; shortcut.released = { releases += 1 }; shortcut.handsFree = { handsFree += 1 }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<2 {
            let down = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: true)); down.flags = [.maskControl, .maskAlternate]
            let up = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: false)); up.flags = [.maskControl, .maskAlternate]
            shortcut.handle(.keyDown, down); shortcut.handle(.keyUp, up)
        }
        XCTAssertEqual(presses, 2); XCTAssertEqual(releases, 0); XCTAssertEqual(handsFree, 0)
        shortcut.stop()
    }
}
