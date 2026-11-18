import XCTest
@preconcurrency import AVFoundation
@preconcurrency import Speech
@testable import SottoAudio

private actor SyntheticAppleCapture: StreamingAudioCapture {
    let pair = AsyncThrowingStream<Data, Error>.makeStream()
    func start(deviceID: UInt32, token: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) -> AsyncThrowingStream<Data, Error> { pair.stream }
    func push(_ data: Data) { pair.continuation.yield(data) }
    func finish(_ token: SpeechSessionToken) { pair.continuation.finish() }
    func cancel(_ token: SpeechSessionToken) { pair.continuation.finish(throwing: CancellationError()) }
}
private final class ModernPartialProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double?
    func accept(_ update: SpeechUpdate) -> Bool {
        lock.withLock {
            guard time == nil, case .hypothesis(let value) = update, !value.provisional.isEmpty else { return false }
            time = ProcessInfo.processInfo.systemUptime; return true
        }
    }
    var first: Double? { lock.withLock { time } }
}

final class LiveModernSpeechTests: XCTestCase, @unchecked Sendable {
    @MainActor func testActualAppleAnalyzerDeliversPartialBeforeInputEndsThenConfirmsFinal() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_MODERN_SPEECH_TEST"] == "1" else { throw XCTSkip("Opt-in: on-device synthetic speech analysis; no microphone, cloud or tools") }
        guard #available(macOS 26, *) else { throw XCTSkip("Requires macOS 26 SpeechAnalyzer") }
        if !(await ModernAppleSpeechProvider.isInstalled(locale: "en-US")) {
            guard ProcessInfo.processInfo.environment["SOTTO_PREPARE_SPEECH_ASSETS"] == "1" else { throw XCTSkip("Prepare the English speech assets in Voice settings") }
            try await AppleSpeechResources.prepare(locale: "en-US")
        }
        let audio = SyntheticTranscriptionAudio(), done = expectation(description: "Synthetic speech ready")
        let synthesizer = AVSpeechSynthesizer()
        defer { _ = synthesizer.isSpeaking }
        let utterance = AVSpeechUtterance(string: "Open my Downloads folder, then find my resume, but do not send anything.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.write(utterance) { buffer in
            if let pcm = buffer as? AVAudioPCMBuffer, audio.append(pcm) { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 15)
        let chunks = try audio.result()
        XCTAssertFalse(chunks.isEmpty)
        let capture = SyntheticAppleCapture(), worker = ModernSpeechWorker(microphone: capture), token = SpeechSessionToken(), probe = ModernPartialProbe()
        let partial = expectation(description: "Provisional words arrive while input is still open")
        let start = ProcessInfo.processInfo.systemUptime
        try await SpeechStartupDeadline.run(timeout: .seconds(8), operation: {
            try await worker.start(locale: "en-US", deviceID: 0, token: token) { update in if probe.accept(update) { partial.fulfill() } }
        }, onAbort: { token.cancel(); Task { await worker.cancel(token) } })
        let feeder = Task {
            for chunk in chunks { await capture.push(chunk); try await Task.sleep(for: .seconds(Double(chunk.count) / 48_000)) }
            for _ in 0..<15 { await capture.push(Data(repeating: 0, count: 4_800)); try await Task.sleep(for: .milliseconds(100)) }
        }
        await fulfillment(of: [partial], timeout: 15)
        try await feeder.value
        let inputEnd = ProcessInfo.processInfo.systemUptime
        let text = try await worker.finish(token)
        let end = ProcessInfo.processInfo.systemUptime
        await worker.cancel(token)
        XCTAssertTrue(text.lowercased().contains("download"))
        let first = try XCTUnwrap(probe.first)
        XCTAssertLessThan(first, inputEnd)
        print("Modern Apple synthetic first-partial ms: \((first - start) * 1000); input-end-to-final ms: \((end - inputEnd) * 1000)")
    }
}
