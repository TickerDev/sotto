@preconcurrency import AVFoundation
@preconcurrency import Speech
import CoreMedia
import Foundation

/// Public Apple backend: prefer installed modern on-device speech. Older Macs
/// and unsupported/uninstalled locales retain the existing Apple adapter.
@MainActor public final class AppleSpeechProvider: SpeechRecognitionProvider {
    private var selected: (any SpeechRecognitionProvider)?
    private var generation = UUID()
    public var requiresSpeechAuthorization: Bool { selected?.requiresSpeechAuthorization ?? true }
    public init() {}
    public func start(locale: String, deviceID: UInt32 = 0, onDevice: Bool, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        cancel(); let id = generation
        let provider: any SpeechRecognitionProvider
        if #available(macOS 26, *), await ModernAppleSpeechProvider.isInstalled(locale: locale) {
            provider = ModernAppleSpeechProvider()
        } else { provider = LegacyAppleSpeechProvider() }
        try Task.checkCancellation()
        guard id == generation else { throw CancellationError() }
        selected = provider
        try await provider.start(locale: locale, deviceID: deviceID, onDevice: onDevice, update: update)
    }
    public func finish() async throws -> String { guard let selected else { throw CancellationError() }; return try await selected.finish() }
    public func cancel() { generation = UUID(); selected?.cancel(); selected = nil }
}

@available(macOS 26, *)
@MainActor final class ModernAppleSpeechProvider: SpeechRecognitionProvider {
    var requiresSpeechAuthorization: Bool { false }
    private let worker = ModernSpeechWorker()
    private var token: SpeechSessionToken?
    static func isInstalled(locale: String) async -> Bool {
        guard SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else { return false }
        let module = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        return await AssetInventory.status(forModules: [module]) == .installed
    }
    public func start(locale: String, deviceID: UInt32, onDevice: Bool, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        cancel(); let token = SpeechSessionToken(); self.token = token
        do {
            let permission = AVCaptureDevice.authorizationStatus(for: .audio)
            let allowed = permission == .authorized ? true : permission == .notDetermined ? await AVCaptureDevice.requestAccess(for: .audio) : false
            guard allowed else { throw SpeechError.microphonePermission }
            try token.checkActive(); try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try await worker.start(locale: locale, deviceID: deviceID, token: token, update: update)
            } onCancel: { [worker] in token.cancel(); Task { await worker.cancel(token) } }
        } catch { token.cancel(); await worker.cancel(token); throw error }
    }
    public func finish() async throws -> String {
        guard let token else { throw CancellationError() }
        return try await withTaskCancellationHandler { try await worker.finish(token) } onCancel: { [worker] in token.cancel(); Task { await worker.cancel(token) } }
    }
    public func cancel() {
        guard let token else { return }; token.cancel(); self.token = nil
        Task { [worker] in await worker.cancel(token) }
    }
}

/// Converts the shared 24 kHz capture stream into the transcriber's negotiated
/// format. Every AnalyzerInput owns a newly allocated, never reused buffer.
@available(macOS 26, *)
final class AnalyzerPCMBridge {
    private let source = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private let converter: AVAudioConverter
    init(format: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: source, to: format) else { throw SpeechError.message("Couldn’t prepare the on-device speech audio format.") }
        self.converter = converter
    }
    func convert(_ data: Data) throws -> AnalyzerInput? {
        guard !data.isEmpty, data.count % 2 == 0, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(data.count / 2)) else { return nil }
        input.frameLength = input.frameCapacity
        _ = data.withUnsafeBytes { memcpy(input.int16ChannelData![0], $0.baseAddress!, data.count) }
        let count = AVAudioFrameCount(ceil(Double(input.frameLength) * converter.outputFormat.sampleRate / 24_000) + 64)
        return try output(capacity: count, input: input)
    }
    func flush() throws -> AnalyzerInput? { try output(capacity: 1024, input: nil) }
    private func output(capacity: AVAudioFrameCount, input: AVAudioPCMBuffer?) throws -> AnalyzerInput? {
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { throw SpeechError.message("Couldn’t allocate on-device speech audio.") }
        var supplied = false, error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard let input else { state.pointee = .endOfStream; return nil }
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        guard error == nil, status != .error else { throw SpeechError.message("Couldn’t convert on-device speech audio.") }
        return output.frameLength > 0 ? AnalyzerInput(buffer: output) : nil
    }
}

@available(macOS 26, *)
actor ModernSpeechWorker {
    private let microphone: any StreamingAudioCapture
    init(microphone: any StreamingAudioCapture = RealtimeMicrophone()) { self.microphone = microphone }
    private var token: SpeechSessionToken?
    private var analyzer: SpeechAnalyzer?
    private var bridge: AnalyzerPCMBridge?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var reader: Task<Void, Never>?
    private var feeder: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var transcript = StreamingTranscript()
    private var completed: Result<String, Error>?
    private var waiter: CheckedContinuation<String, Error>?

    func start(locale: String, deviceID: UInt32, token: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        try token.checkActive()
        if let previous = self.token { await cancel(previous) }
        self.token = token; completed = nil; transcript = StreamingTranscript()
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else { throw SpeechError.recognitionUnavailable }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .lingering))
        self.analyzer = analyzer
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { await self?.expire(token, message: "On-device speech did not become ready. Try again.") }
        }
        do {
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw SpeechError.onDeviceUnavailable }
            try token.checkActive()
            bridge = try AnalyzerPCMBridge(format: format)
            try await analyzer.prepareToAnalyze(in: format)
            try token.checkActive()
            let pair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(512)); input = pair.continuation
            reader = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard token.isActive else { return }
                        await self?.received(String(result.text.characters), start: result.range.start.seconds, end: result.range.end.seconds, final: result.isFinal, token: token, update: update)
                    }
                } catch { await self?.failed(error, token: token, update: update) }
            }
            try await analyzer.start(inputSequence: pair.stream)
            let audio = try await microphone.start(deviceID: deviceID, token: token, update: update)
            try token.checkActive()
            deadline?.cancel(); deadline = nil
            feeder = Task { [weak self] in
                do {
                    for try await data in audio { try Task.checkCancellation(); try await self?.feed(data, token: token) }
                    try await self?.finishInput(token)
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    await self?.reader?.value
                    await self?.complete(token)
                } catch { await self?.failed(error, token: token, update: update) }
            }
        } catch {
            let failure: Error
            if case .failure(let reason) = completed { failure = reason } else { failure = error }
            await cancel(token); throw failure
        }
    }
    private func feed(_ data: Data, token: SpeechSessionToken) throws {
        try token.checkActive(); guard self.token === token else { throw CancellationError() }
        if let value = try bridge?.convert(data), case .dropped = input?.yield(value) { throw SpeechError.message("On-device speech couldn’t keep up. Recording was discarded.") }
    }
    private func finishInput(_ token: SpeechSessionToken) throws {
        try token.checkActive()
        if let value = try bridge?.flush(), case .dropped = input?.yield(value) { throw SpeechError.message("On-device speech couldn’t finish this recording.") }
        input?.finish(); input = nil
    }
    private func received(_ text: String, start: Double, end: Double, final: Bool, token: SpeechSessionToken, update: @Sendable (SpeechUpdate) -> Void) {
        guard self.token === token, token.isActive else { return }
        transcript.receive(text: text, start: start, end: end, final: final)
        update(.hypothesis(transcript.snapshot))
    }
    private func complete(_ token: SpeechSessionToken) {
        guard self.token === token, token.isActive, completed == nil else { return }
        let snapshot = transcript.snapshot
        if !snapshot.provisional.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { completed = .failure(SpeechError.message("Speech wasn’t finalized. The recording was discarded; please try again.")) }
        else { completed = .success(snapshot.confirmed) }
        resolve()
    }
    private func failed(_ error: Error, token: SpeechSessionToken, update: @Sendable (SpeechUpdate) -> Void) {
        guard self.token === token, token.isActive, completed == nil else { return }
        completed = .failure(error); resolve()
        update(.failure("On-device speech stopped before confirming your request. Please try again."))
    }
    func finish(_ token: SpeechSessionToken) async throws -> String {
        guard self.token === token else { throw CancellationError() }; try token.checkActive()
        try await microphone.finish(token)
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { await self?.expire(token, message: "Speech finalization timed out. The recording was discarded.") }
        }
        return try await withCheckedThrowingContinuation { waiter = $0; resolve() }
    }
    private func resolve() {
        guard let completed, let waiter else { return }; self.waiter = nil
        deadline?.cancel(); deadline = nil; waiter.resume(with: completed)
    }
    private func expire(_ token: SpeechSessionToken, message: String) async {
        guard self.token === token, token.isActive else { return }
        completed = .failure(SpeechError.message(message)); resolve()
        await cancel(token)
    }
    func cancel(_ token: SpeechSessionToken) async {
        guard self.token === token else { return }; self.token = nil; token.cancel()
        deadline?.cancel(); deadline = nil; input?.finish(); input = nil
        feeder?.cancel(); feeder = nil; reader?.cancel(); reader = nil
        waiter?.resume(throwing: CancellationError()); waiter = nil
        let analyzer = self.analyzer; self.analyzer = nil; bridge = nil
        await microphone.cancel(token); await analyzer?.cancelAndFinishNow()
    }
}
