import XCTest
@preconcurrency import AVFoundation
import SottoSecurity
@testable import SottoAudio

final class SyntheticTranscriptionAudio: @unchecked Sendable {
    private let lock = NSLock()
    private let encoder = RealtimePCMEncoder()
    private var frames: [Data] = []
    private var failure: Error?
    private var finished = false
    func append(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.withLock {
            guard !finished else { return false }
            if buffer.frameLength == 0 {
                do { let tail = try encoder.finish(); if !tail.isEmpty { frames.append(tail) } } catch { failure = error }
                finished = true; return true
            }
            do { let data = try encoder.encode(buffer); if !data.isEmpty { frames.append(data) } }
            catch { failure = error }
            return false
        }
    }
    func result() throws -> [Data] { try lock.withLock { if let failure { throw failure }; return frames } }
}

final class LiveRealtimeTranscriptionTests: XCTestCase, @unchecked Sendable {
    @MainActor func testLiveSyntheticSpeechRoundTripWithoutMicrophoneOrAgentActions() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_REALTIME_TEST"] == "1" else {
            throw XCTSkip("Opt-in: sends synthetic speech to OpenAI using the saved API key; API billing applies. No microphone or agent tools.")
        }
        guard let key = try await KeychainCredentials.shared.read(), !key.isEmpty else { throw XCTSkip("No saved OpenAI API key") }
        let audio = SyntheticTranscriptionAudio()
        let done = expectation(description: "Synthetic speech rendered")
        let synthesizer = AVSpeechSynthesizer()
        defer { _ = synthesizer.isSpeaking }
        let utterance = AVSpeechUtterance(string: "Open my Downloads folder.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.write(utterance) { buffer in
            guard let buffer = buffer as? AVAudioPCMBuffer else { return }
            if audio.append(buffer) { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 15)
        let chunks = try audio.result()
        XCTAssertFalse(chunks.isEmpty)
        let stream = AsyncThrowingStream<Data, Error>.makeStream()
        for chunk in chunks { stream.continuation.yield(chunk) }
        stream.continuation.finish()
        let session = RealtimeTranscriptionSession(socket: OpenAITranscriptionSocket(key: key))
        let transcript = try await session.transcribe(stream.stream, locale: "en-US") { _ in }
        XCTAssertTrue(transcript.lowercased().contains("download"), "Expected the synthetic Downloads request to be transcribed")
    }
}
