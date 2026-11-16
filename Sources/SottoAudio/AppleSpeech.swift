@preconcurrency import AVFoundation
@preconcurrency import Speech
import AudioToolbox
import CoreAudio
import SottoAudioBridge
import Foundation
import OSLog

public enum SpeechUpdate: Sendable { case level(Float), transcript(String), hypothesis(SpeechTranscript), failure(String), inputUnavailable(String) }
@MainActor public protocol SpeechRecognitionProvider: AnyObject {
    var requiresSpeechAuthorization: Bool { get }
    func start(locale: String, deviceID: UInt32, onDevice: Bool, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws
    func finish() async throws -> String
    func cancel()
}
public extension SpeechRecognitionProvider { var requiresSpeechAuthorization: Bool { true } }
public enum SpeechError: LocalizedError {
    case message(String), microphonePermission, speechPermission, microphoneUnavailable(String), onDeviceUnavailable, recognitionUnavailable
    public var errorDescription: String? {
        switch self {
        case .message(let text), .microphoneUnavailable(let text): text
        case .microphonePermission: "Microphone access is not allowed. Enable Sotto in System Settings → Privacy & Security → Microphone."
        case .speechPermission: "Speech Recognition access is not allowed. Enable Sotto in System Settings → Privacy & Security → Speech Recognition."
        case .onDeviceUnavailable: "On-device speech is unavailable for this language. Choose another language or allow Apple processing in Voice settings."
        case .recognitionUnavailable: "Apple Speech is currently unavailable for this language. Check Voice settings and try again."
        }
    }
}
@MainActor final class LegacyAppleSpeechProvider: SpeechRecognitionProvider {
    private let worker = AppleSpeechWorker()
    private var session: SpeechSessionToken?
    public init() {}
    public func start(locale: String, deviceID: UInt32 = 0, onDevice: Bool, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        let started = ContinuousClock.now
        cancel()
        let session = SpeechSessionToken(); self.session = session
        do {
            let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            let microphoneAllowed = microphone == .authorized ? true : microphone == .notDetermined ? await AVCaptureDevice.requestAccess(for: .audio) : false
            guard microphoneAllowed else { throw SpeechError.microphonePermission }
            let currentStatus = SFSpeechRecognizer.authorizationStatus()
            let status = currentStatus == .notDetermined ? await SpeechAuthorization.request() : currentStatus
            try Task.checkCancellation(); try session.checkActive()
            guard status == .authorized else { throw SpeechError.speechPermission }
            try await withTaskCancellationHandler {
                try await worker.start(locale: locale, deviceID: deviceID, onDevice: onDevice, session: session, update: update)
            } onCancel: { [worker] in
                session.cancel(); Task { await worker.cancel(session) }
            }
            try session.checkActive()
            Logger(subsystem: "org.sotto.mac", category: "latency").notice("Microphone startup including authorization: \(String(describing: started.duration(to: .now)), privacy: .public)")
        } catch {
            session.cancel(); await worker.cancel(session)
            if self.session === session { self.session = nil }
            throw error
        }
    }
    public func finish() async throws -> String {
        guard let session else { throw CancellationError() }
        return try await withTaskCancellationHandler { try await worker.finish(session) } onCancel: { [worker] in
            session.cancel(); Task { await worker.cancel(session) }
        }
    }
    public func cancel() {
        guard let session else { return }
        session.cancel(); self.session = nil
        Task { [worker] in await worker.cancel(session) }
    }
}

/// Invalidated synchronously even while a device driver blocks the audio actor.
/// Every buffer/result checks this token; stale teardown cannot cancel a newer session.
final class SpeechSessionToken: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var receivedAudio = false
    var isActive: Bool { lock.withLock { active } }
    var hasAudio: Bool { lock.withLock { receivedAudio } }
    /// nil discards a canceled buffer; true identifies the first accepted buffer.
    func acceptBuffer() -> Bool? {
        lock.withLock {
            guard active else { return nil }
            let first = !receivedAudio; receivedAudio = true; return first
        }
    }
    func cancel() { lock.withLock { active = false } }
    func checkActive() throws { if !isActive { throw CancellationError() } }
}

/// All engine construction, device routing, prepare/start/stop and recognizer
/// lifecycle work is serialized away from MainActor. No idle microphone prewarming.
actor AppleSpeechWorker {
    private let didEnterStartup: @Sendable () -> Void
    init(didEnterStartup: @escaping @Sendable () -> Void = {}) { self.didEnterStartup = didEnterStartup }
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var configurationObserver: NSObjectProtocol?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var completion: CheckedContinuation<String, Error>?
    private var finalizationTimeout: Task<Void, Never>?
    private var finalText: String?
    private var failure: String?
    private var tapped = false
    private var session: SpeechSessionToken?
    private var configurationGuard: AudioConfigurationGuard?
    private var startupCompletion: CheckedContinuation<Void, Error>?
    private var startupTimeout: Task<Void, Never>?

    func start(locale: String, deviceID: UInt32, onDevice: Bool, session: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        didEnterStartup()
        // Check before cleanup: a canceled queued start must not tear down a newer session.
        try session.checkActive()
        reset(); self.session = session
        do {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else { throw SpeechError.recognitionUnavailable }
            if onDevice && !recognizer.supportsOnDeviceRecognition { throw SpeechError.onDeviceUnavailable }
            self.recognizer = recognizer
            let engine = AVAudioEngine(); self.engine = engine
            _ = try CaptureInput.configure(engine, deviceID: deviceID)
            let input = engine.inputNode
            try session.checkActive()
            let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true; request.requiresOnDeviceRecognition = onDevice
            self.request = request
            try installTap(input: input, request: request, session: session, update: update)
            guard let configuration = inputConfiguration(), configuration.isUsable else { throw SpeechError.microphoneUnavailable("Could not verify the selected microphone input") }
            configurationGuard = AudioConfigurationGuard(expected: configuration)
            recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                guard session.isActive else { return }
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let message = error?.localizedDescription
                Task { await self?.receive(text: text, isFinal: isFinal, message: message, session: session, update: update) }
            }
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { @Sendable [weak self] _ in
                guard session.isActive else { return }
                // Never stop or destroy the engine on its notification queue.
                Task { await self?.configurationChanged(session, update: update) }
            }
            try session.checkActive(); try startEngine(engine); try session.checkActive()
            // A successful start() is not proof that audio is arriving yet.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if session.hasAudio { continuation.resume(); return }
                startupCompletion = continuation
                startupTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled, let self else { return }
                    await self.startupTimedOut(session)
                }
            }
        } catch {
            if self.session === session { reset() }
            throw error
        }
    }
    private func installTap(input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest, session: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) throws {
        let error = SottoInstallMicrophoneTap(input) { @Sendable [weak self] buffer, _ in
            guard buffer.frameLength > 0, let first = session.acceptBuffer() else { return }
            request.append(buffer)
            if first { Task { await self?.audioStarted(session) } }
            if let samples = buffer.floatChannelData?[0] {
                var sum: Float = 0; for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
                update(.level(min(1, sqrt(sum / Float(buffer.frameLength)) * 8)))
            }
        }
        if let error { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
        tapped = true
    }
    private func startEngine(_ engine: AVAudioEngine) throws {
        if let error = SottoStartAudioEngine(engine) { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
    }
    private func inputConfiguration() -> AudioInputConfiguration? {
        engine.flatMap(CaptureInput.configuration)
    }
    private func configurationChanged(_ session: SpeechSessionToken, update: @escaping @Sendable (SpeechUpdate) -> Void) {
        guard self.session === session, session.isActive, tapped, let engine, var policy = configurationGuard else { return }
        let current = inputConfiguration()
        let inputUnchanged = current == policy.expected
        let action = policy.evaluate(current: current, running: engine.isRunning, hasAudio: session.hasAudio)
        configurationGuard = policy
        Logger(subsystem: "org.sotto.mac", category: "audio-route").notice("Configuration notification: running=\(engine.isRunning), inputUnchanged=\(inputUnchanged), hasAudio=\(session.hasAudio), action=\(String(describing: action), privacy: .public)")
        switch action {
        case .ignore: return
        case .discard:
            failConfiguration(session, message: "The microphone input changed or became unavailable. Recording was discarded; choose an available input and try again.", update: update)
        case .restart, .rebuildStartupTap:
            do {
                try session.checkActive()
                if let error = SottoStopAudioEngine(engine, action == .rebuildStartupTap) { throw SpeechError.microphoneUnavailable(error.localizedDescription) }
                if action == .rebuildStartupTap {
                    guard !session.hasAudio else { throw SpeechError.message("Audio arrived before the input format stabilized") }
                    tapped = false
                    guard let request else { throw CancellationError() }
                    try installTap(input: engine.inputNode, request: request, session: session, update: update)
                }
                try session.checkActive(); try startEngine(engine); try session.checkActive()
                guard inputConfiguration() == policy.expected else { throw SpeechError.message("Microphone input did not stabilize") }
            } catch {
                failConfiguration(session, message: "The microphone could not resume after an audio configuration change. Recording was discarded; try again or choose another input.", update: update)
            }
        }
    }
    private func audioStarted(_ session: SpeechSessionToken) {
        guard self.session === session, session.isActive else { return }
        startupTimeout?.cancel(); startupTimeout = nil
        startupCompletion?.resume(); startupCompletion = nil
    }
    private func startupTimedOut(_ session: SpeechSessionToken) {
        guard self.session === session, startupCompletion != nil else { return }
        let continuation = startupCompletion; startupCompletion = nil
        reset()
        continuation?.resume(throwing: SpeechError.microphoneUnavailable("No audio arrived from the selected microphone."))
    }
    private func failConfiguration(_ session: SpeechSessionToken, message: String, update: @Sendable (SpeechUpdate) -> Void) {
        guard self.session === session else { return }
        let continuation = startupCompletion; startupCompletion = nil
        reset()
        continuation?.resume(throwing: SpeechError.microphoneUnavailable(message))
        update(.inputUnavailable(message))
    }
    private func receive(text: String?, isFinal: Bool, message: String?, session: SpeechSessionToken, update: @Sendable (SpeechUpdate) -> Void) {
        guard self.session === session, session.isActive else { return }
        if let text {
            update(.hypothesis(isFinal ? SpeechTranscript(confirmed: text) : SpeechTranscript(provisional: text)))
            if isFinal { finalText = text }
        }
        if let message, finalText == nil {
            failure = message
            if completion == nil && engine?.isRunning == true { update(.failure(message)) }
        }
        resolveIfReady()
    }
    private func stopInput() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver); self.configurationObserver = nil }
        if let engine { _ = SottoStopAudioEngine(engine, tapped) }
        tapped = false
        request?.endAudio()
    }
    func finish(_ session: SpeechSessionToken) async throws -> String {
        guard self.session === session else { throw CancellationError() }
        try session.checkActive(); stopInput()
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation; resolveIfReady()
            finalizationTimeout?.cancel()
            finalizationTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self else { return }
                await self.timeout(session)
            }
        }
    }
    private func timeout(_ session: SpeechSessionToken) {
        guard self.session === session, completion != nil else { return }
        failure = "Speech recognition timed out. Please try again."; resolveIfReady()
    }
    private func resolveIfReady() {
        guard let continuation = completion else { return }
        if let finalText { completion = nil; finalizationTimeout?.cancel(); continuation.resume(returning: finalText) }
        else if let failure { completion = nil; finalizationTimeout?.cancel(); continuation.resume(throwing: SpeechError.message(failure)) }
    }
    func cancel(_ session: SpeechSessionToken) {
        guard self.session === session else { return }
        reset()
    }
    private func reset() {
        session?.cancel(); session = nil
        stopInput(); recognition?.cancel(); recognition = nil; recognizer = nil; engine = nil; request = nil
        configurationGuard = nil; startupTimeout?.cancel(); startupTimeout = nil
        startupCompletion?.resume(throwing: CancellationError()); startupCompletion = nil
        finalizationTimeout?.cancel(); finalizationTimeout = nil
        completion?.resume(throwing: CancellationError()); completion = nil; finalText = nil; failure = nil
    }
}
@MainActor public protocol SpeechSynthesisProvider { func speak(_ text: String); func stop() }
@MainActor public final class AppleSpeechSynthesis: SpeechSynthesisProvider {
    private let synthesizer = AVSpeechSynthesizer()
    public init() {}
    public func speak(_ text: String) { synthesizer.speak(AVSpeechUtterance(string: text)) }
    public func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
