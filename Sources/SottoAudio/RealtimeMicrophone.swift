@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OSLog
import SottoAudioBridge

/// The audio tap is serial; the lock also makes format replacement safe during
/// initial hardware settling. No AVAudioPCMBuffer crosses an actor boundary.
final class RealtimePCMEncoder: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    static func level(_ pcm: Data) -> Float {
        guard pcm.count >= 2 else { return 0 }
        return pcm.withUnsafeBytes { bytes in
            var sum: Float = 0
            for offset in stride(from: 0, to: pcm.count - 1, by: 2) {
                let sample = Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))) / 32768
                sum += sample * sample
            }
            return min(1, sqrt(sum / Float(pcm.count / 2)) * 8)
        }
    }
    func finish() throws -> Data {
        try lock.withLock {
            guard let converter, let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 1024) else { return Data() }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in state.pointee = .endOfStream; return nil }
            guard status != .error, error == nil, let samples = output.int16ChannelData?[0] else { throw SpeechError.message("Couldn’t finish converting microphone audio.") }
            return Data(bytes: samples, count: Int(output.frameLength) * 2)
        }
    }
    func encode(_ input: AVAudioPCMBuffer) throws -> Data {
        try lock.withLock {
            guard input.frameLength > 0, input.format.sampleRate > 0,
                  let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true) else { throw SpeechError.message("Invalid microphone audio format.") }
            if inputFormat != input.format {
                guard let value = AVAudioConverter(from: input.format, to: outputFormat) else { throw SpeechError.message("Couldn’t convert microphone audio.") }
                value.downmix = true; converter = value; inputFormat = input.format
            }
            let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 24_000 / input.format.sampleRate) + 64)
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity), let converter else { throw SpeechError.message("Couldn’t allocate transcription audio.") }
            var supplied = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, result in
                if supplied { result.pointee = .noDataNow; return nil }
                supplied = true; result.pointee = .haveData; return input
            }
            guard status != .error, error == nil, let samples = output.int16ChannelData?[0] else { throw SpeechError.message("Couldn’t convert microphone audio.") }
            // macOS supported architectures are little-endian; the API expects
            // signed little-endian PCM16 mono, never a WAV header or float bytes.
            return Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
        }
    }
}

protocol StreamingAudioCapture: Sendable {
    func start(deviceID: UInt32, token: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws -> AsyncThrowingStream<Data, Error>
    func finish(_ token: SpeechSessionToken) async throws
    func cancel(_ token: SpeechSessionToken) async
}

actor RealtimeMicrophone: StreamingAudioCapture {
    private var engine: AVAudioEngine?
    private var token: SpeechSessionToken?
    private var stream: AsyncThrowingStream<Data, Error>.Continuation?
    private var observer: NSObjectProtocol?
    private var startup: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var encoder: RealtimePCMEncoder?
    private var configurationGuard: AudioConfigurationGuard?
    private var tapped = false

    func start(deviceID: UInt32, token: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws -> AsyncThrowingStream<Data, Error> {
        try token.checkActive()
        reset(); self.token = token
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(512))
        stream = pair.continuation
        let engine = AVAudioEngine(); self.engine = engine
        do {
            let configuration = try CaptureInput.configure(engine, deviceID: deviceID)
            configurationGuard = AudioConfigurationGuard(expected: configuration)
            let input = engine.inputNode
            let encoder = RealtimePCMEncoder()
            self.encoder = encoder
            try installTap(input, encoder: encoder, continuation: pair.continuation, token: token, update: update)
            Logger(subsystem: "org.sotto.mac", category: "audio-route").notice("Capture input verified: device=\(configuration.deviceID), rate=\(configuration.sampleRate), outputDisabled=true")
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                Task { await self?.configurationChanged(token, update: update) }
            }
            try token.checkActive()
            if let error = SottoStartAudioEngine(engine) { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
            try await withCheckedThrowingContinuation { continuation in
                if token.hasAudio { continuation.resume(); return }
                startup = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled { await self?.startupExpired(token) }
                }
            }
            try token.checkActive()
            return pair.stream
        } catch { if self.token === token { reset() }; throw error }
    }
    private func installTap(_ input: AVAudioInputNode, encoder: RealtimePCMEncoder, continuation: AsyncThrowingStream<Data, Error>.Continuation, token: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) throws {
        let error = SottoInstallMicrophoneTap(input) { @Sendable [weak self] buffer, _ in
                guard buffer.frameLength > 0, let first = token.acceptBuffer() else { return }
                do {
                    let data = try encoder.encode(buffer)
                    if !data.isEmpty, case .dropped = continuation.yield(data) {
                        throw SpeechError.message("The transcription connection couldn’t keep up. Recording was discarded; try again.")
                    }
                    if first { Task { await self?.audioStarted(token) } }
                    update(.level(RealtimePCMEncoder.level(data)))
                } catch {
                    token.cancel(); continuation.finish(throwing: error)
                    update(.failure(error.localizedDescription))
                    Task { await self?.cancel(token) }
                }
        }
        if let error { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
        tapped = true
    }
    private func audioStarted(_ token: SpeechSessionToken) {
        guard self.token === token, token.isActive else { return }
        timeout?.cancel(); timeout = nil; startup?.resume(); startup = nil
    }
    private func startupExpired(_ token: SpeechSessionToken) {
        guard self.token === token else { return }
        let pending = startup; startup = nil
        reset(); pending?.resume(throwing: SpeechError.microphoneUnavailable("No audio arrived from the selected microphone."))
    }
    private func configurationChanged(_ token: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) {
        guard self.token === token, token.isActive, tapped, let engine, var policy = configurationGuard else { return }
        let current = CaptureInput.configuration(engine)
        let unchanged = current == policy.expected
        let action = policy.evaluate(current: current, running: engine.isRunning, hasAudio: token.hasAudio)
        configurationGuard = policy
        Logger(subsystem: "org.sotto.mac", category: "audio-route").notice("Capture configuration: running=\(engine.isRunning), inputUnchanged=\(unchanged), hasAudio=\(token.hasAudio), action=\(String(describing: action), privacy: .public)")
        switch action {
        case .ignore: return
        case .restart, .rebuildStartupTap:
            do {
                try token.checkActive()
                if let error = SottoStopAudioEngine(engine, action == .rebuildStartupTap) { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
                if action == .rebuildStartupTap {
                    tapped = false
                    guard !token.hasAudio, let encoder, let stream else { throw CancellationError() }
                    try installTap(engine.inputNode, encoder: encoder, continuation: stream, token: token, update: update)
                }
                if let error = SottoStartAudioEngine(engine) { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
                try token.checkActive()
                guard CaptureInput.configuration(engine) == policy.expected else { throw SpeechError.microphoneUnavailable("The microphone input did not stabilize.") }
            } catch { failConfiguration(token, update: update) }
        case .discard: failConfiguration(token, update: update)
        }
    }
    private func failConfiguration(_ token: SpeechSessionToken, update: @Sendable (SpeechUpdate) -> Void) {
        guard self.token === token else { return }
        let pending = startup; startup = nil
        reset()
        pending?.resume(throwing: SpeechError.microphoneUnavailable("The microphone input changed."))
        update(.inputUnavailable("The microphone input changed. Start a fresh recording."))
    }
    func finish(_ token: SpeechSessionToken) throws {
        guard self.token === token else { throw CancellationError() }
        try token.checkActive()
        stopEngine()
        if let tail = try encoder?.finish(), !tail.isEmpty, case .dropped = stream?.yield(tail) {
            throw SpeechError.message("The transcription connection couldn’t keep up. Recording was discarded.")
        }
        encoder = nil; stream?.finish(); stream = nil
    }
    func cancel(_ token: SpeechSessionToken) { if self.token === token { reset() } }
    private func stopEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        if let engine { _ = SottoStopAudioEngine(engine, tapped) }
        engine = nil; tapped = false; configurationGuard = nil
    }
    private func reset() {
        token?.cancel(); token = nil; timeout?.cancel(); timeout = nil
        encoder = nil
        startup?.resume(throwing: CancellationError()); startup = nil
        stopEngine(); stream?.finish(throwing: CancellationError()); stream = nil
    }
}
