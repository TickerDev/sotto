import XCTest
@preconcurrency import AVFoundation
import SottoTools
import SottoSecurity
@testable import SottoAudio
@testable import SottoUI

private actor TranscriptionFixtureSocket: TranscriptionSocket {
    var sent: [Data] = []
    private var events: [Data] = []
    private var waiting: CheckedContinuation<Data, Error>?
    var closed = false
    let completes: Bool
    init(completes: Bool = true) { self.completes = completes }
    func send(_ data: Data) throws {
        guard !closed else { throw CancellationError() }
        sent.append(data)
        let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        switch value["type"] as? String {
        case "session.update": push(try RealtimeTranscriptionWire.json(["type": "session.updated", "session": ["type": "transcription"]]))
        case "input_audio_buffer.commit" where completes:
            push(try RealtimeTranscriptionWire.json(["type": "input_audio_buffer.committed", "item_id": "own-recording"]))
            push(try RealtimeTranscriptionWire.json(["type": "conversation.item.input_audio_transcription.completed", "item_id": "other-recording", "transcript": "Wrong recording"]))
            push(try RealtimeTranscriptionWire.json(["type": "conversation.item.input_audio_transcription.delta", "item_id": "own-recording", "delta": "Open Downloads"]))
            push(try RealtimeTranscriptionWire.json(["type": "conversation.item.input_audio_transcription.completed", "item_id": "own-recording", "transcript": "Open my Downloads folder"]))
        default: break
        }
    }
    private func push(_ data: Data) {
        if let waiting { self.waiting = nil; waiting.resume(returning: data) }
        else { events.append(data) }
    }
    func receive() async throws -> Data {
        if closed { throw CancellationError() }
        if !events.isEmpty { return events.removeFirst() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func close() { closed = true; waiting?.resume(throwing: CancellationError()); waiting = nil }
}

private actor RealtimeKeyProbe {
    var reads = 0
    func read() -> String? { reads += 1; return "fixture-key" }
}

final class RealtimeTranscriptionTests: XCTestCase, @unchecked Sendable {
    func testWireUsesTranscriptionOnlyAndManualCommitWithDocumentedAudioFormat() throws {
        let data = try RealtimeTranscriptionWire.configure(locale: "en-US")
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let session = root["session"] as! [String: Any]
        let input = (session["audio"] as! [String: Any])["input"] as! [String: Any]
        XCTAssertEqual(session["type"] as? String, "transcription")
        XCTAssertEqual((input["format"] as? [String: Any])?["rate"] as? Int, 24_000)
        XCTAssertEqual((input["transcription"] as? [String: Any])?["model"] as? String, "gpt-live-transcribe")
        XCTAssertEqual((input["transcription"] as? [String: Any])?["languages"] as? [String], ["en"])
        XCTAssertTrue(input["turn_detection"] is NSNull)
        XCTAssertNil(session["tools"])
        XCTAssertEqual(RealtimeTranscriptionWire.endpoint.absoluteString, "wss://api.openai.com/v1/realtime?intent=transcription")
        XCTAssertThrowsError(try RealtimeTranscriptionWire.configure(locale: "not-supported"))
    }
    func testPCMAppendPreservesBytesAndRejectsInvalidBuffers() throws {
        let pcm = Data([0, 0, 255, 127])
        let event = try JSONSerialization.jsonObject(with: RealtimeTranscriptionWire.append(pcm)) as! [String: Any]
        XCTAssertEqual(Data(base64Encoded: event["audio"] as! String), pcm)
        XCTAssertThrowsError(try RealtimeTranscriptionWire.append(Data()))
        XCTAssertThrowsError(try RealtimeTranscriptionWire.append(Data([0])))
    }
    func testFinalTranscriptRequiresMatchingCommittedItemEvenWithReorderedEvents() throws {
        var state = RealtimeTranscriptState()
        _ = try state.consume(RealtimeTranscriptionWire.json(["type": "conversation.item.input_audio_transcription.completed", "item_id": "correct", "transcript": "Final text"]))
        XCTAssertNil(state.final)
        _ = try state.consume(RealtimeTranscriptionWire.json(["type": "conversation.item.input_audio_transcription.completed", "item_id": "wrong", "transcript": "Wrong text"]))
        _ = try state.consume(RealtimeTranscriptionWire.json(["type": "input_audio_buffer.committed", "item_id": "correct"]))
        XCTAssertEqual(state.final, "Final text")
    }
    func testPartialsNeverCountAsFinalAndServerErrorsDoNotEchoPrivateText() throws {
        var state = RealtimeTranscriptState()
        let partial = try state.consume(RealtimeTranscriptionWire.json(["type": "conversation.item.input_audio_transcription.delta", "item_id": "item", "delta": "Do something"]))
        XCTAssertEqual(partial, "Do something"); XCTAssertNil(state.final)
        do {
            _ = try state.consume(RealtimeTranscriptionWire.json(["type": "error", "error": ["code": "unexpected", "message": "private-transcript-marker"]]))
            XCTFail("Server error was ignored")
        } catch { XCTAssertFalse(error.localizedDescription.contains("private-transcript-marker")) }
    }
    func testSessionSendsAllAudioBeforeExactlyOneCommitAndReturnsOnlyOwnedFinal() async throws {
        let socket = TranscriptionFixtureSocket(), stream = AsyncThrowingStream<Data, Error>.makeStream()
        stream.continuation.yield(Data(repeating: 0, count: 9_600)); stream.continuation.finish()
        let session = RealtimeTranscriptionSession(socket: socket)
        let result = try await session.transcribe(stream.stream, locale: "en-US") { _ in }
        XCTAssertEqual(result, "Open my Downloads folder")
        let sent = await socket.sent
        let types = try sent.map { (try JSONSerialization.jsonObject(with: $0) as! [String: Any])["type"] as! String }
        XCTAssertEqual(types, ["session.update", "input_audio_buffer.append", "input_audio_buffer.commit"])
        let closed = await socket.closed
        XCTAssertTrue(closed)
    }
    func testCancellationClosesConnectionAndDoesNotCommitPendingAudio() async throws {
        let socket = TranscriptionFixtureSocket(completes: false), stream = AsyncThrowingStream<Data, Error>.makeStream()
        let session = RealtimeTranscriptionSession(socket: socket)
        let task = Task { try await session.transcribe(stream.stream, locale: "en-US") { _ in } }
        for _ in 0..<100 { if await socket.sent.count > 0 { break }; try await Task.sleep(for: .milliseconds(2)) }
        task.cancel(); stream.continuation.finish(throwing: CancellationError())
        do { _ = try await task.value; XCTFail("Cancelled recording returned a transcript") } catch is CancellationError {}
        let sent = await socket.sent
        XCTAssertFalse(try sent.contains { (try JSONSerialization.jsonObject(with: $0) as! [String: Any])["type"] as? String == "input_audio_buffer.commit" })
        let closed = await socket.closed
        XCTAssertTrue(closed)
    }
    func testMissingFinalTranscriptTimesOutWithoutReturningPartialText() async throws {
        let socket = TranscriptionFixtureSocket(completes: false), stream = AsyncThrowingStream<Data, Error>.makeStream()
        stream.continuation.yield(Data(repeating: 0, count: 9_600)); stream.continuation.finish()
        let session = RealtimeTranscriptionSession(socket: socket, finalTimeout: .milliseconds(25))
        do { _ = try await session.transcribe(stream.stream, locale: "en-US") { _ in }; XCTFail("Missing final transcript was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        let closed = await socket.closed
        XCTAssertTrue(closed)
    }
    func testTooShortRecordingNeverCommitsOrInventsAudio() async throws {
        let socket = TranscriptionFixtureSocket(), stream = AsyncThrowingStream<Data, Error>.makeStream()
        stream.continuation.yield(Data(repeating: 0, count: 100)); stream.continuation.finish()
        let session = RealtimeTranscriptionSession(socket: socket)
        do { _ = try await session.transcribe(stream.stream, locale: "en-US") { _ in }; XCTFail("Too-short recording was committed") }
        catch { XCTAssertTrue(error.localizedDescription.contains("too short")) }
        let sent = await socket.sent
        XCTAssertEqual(sent.count, 2)
    }
    func testPCMConverterProducesMonoInt16At24kFrom48kStereo() throws {
        let input = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!, frameCapacity: 4_800)!
        input.frameLength = 4_800
        for channel in 0..<2 { for frame in 0..<4_800 { input.floatChannelData![channel][frame] = sin(Float(frame) * 0.1) * 0.2 } }
        let encoder = RealtimePCMEncoder()
        var bytes = 0
        for _ in 0..<4 { bytes += try encoder.encode(input).count }
        bytes += try encoder.finish().count
        XCTAssertGreaterThan(bytes, 17_000)
        XCTAssertLessThanOrEqual(bytes, 19_200)
        XCTAssertEqual(bytes % 2, 0)
        XCTAssertEqual(RealtimePCMEncoder.level(Data(repeating: 0, count: 20)), 0)
        XCTAssertGreaterThan(RealtimePCMEncoder.level(Data([0, 32, 0, 32])), 0)
    }
    func testSpeechPreferencesMigrateToAppleAndKeepAudioConsentSeparateFromReasoning() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data(#"{"remoteConsent":true}"#.utf8))
        XCTAssertEqual(legacy.speechBackend, .apple); XCTAssertFalse(legacy.remoteSpeechConsent)
        var prefs = Preferences(); prefs.speechBackend = .openAIRealtime; prefs.remoteSpeechConsent = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded.speechBackend, .openAIRealtime); XCTAssertTrue(decoded.remoteSpeechConsent)
        XCTAssertFalse(decoded.remoteConsent); XCTAssertTrue(decoded.automaticIntelligence)
    }
    @MainActor func testAudioConsentBlocksBeforeReadingKeyOrStartingMicrophone() async throws {
        let probe = RealtimeKeyProbe()
        let connection = ProviderConnection(credentials: RealtimeFixtureCredentials(probe: probe))
        var prefs = Preferences(); prefs.speechBackend = .openAIRealtime
        let model = AppModel(providerConnection: connection, preferences: prefs, startServices: false)
        defer { model.shutdown() }
        model.beginListening()
        XCTAssertEqual(model.state, .failed)
        XCTAssertTrue(model.reply.contains("Allow audio"))
        let reads = await probe.reads
        XCTAssertEqual(reads, 0)
    }
}

private struct RealtimeFixtureCredentials: CredentialStorage {
    let probe: RealtimeKeyProbe
    func containsKey() async throws -> Bool { true }
    func read() async throws -> String? { await probe.read() }
    func save(_ key: String) async throws {}
}
