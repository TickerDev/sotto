@preconcurrency import AVFoundation
import Foundation

@MainActor public final class OpenAIRealtimeSpeechProvider: SpeechRecognitionProvider {
    public var requiresSpeechAuthorization: Bool { false }
    private let readKey: @Sendable () async throws -> String?
    private let capture = RealtimeMicrophone()
    private var token: SpeechSessionToken?
    private var network: RealtimeTranscriptionSession?
    private var transcription: Task<String, Error>?
    public init(readKey: @escaping @Sendable () async throws -> String?) { self.readKey = readKey }

    public func start(locale: String, deviceID: UInt32, onDevice: Bool, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws {
        cancel()
        let token = SpeechSessionToken(); self.token = token
        do {
            guard let key = try await readKey(), !key.isEmpty else { throw SpeechError.message("Add your OpenAI API key in Voice settings to use Realtime transcription.") }
            try token.checkActive(); try Task.checkCancellation()
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            let allowed: Bool
            if status == .authorized { allowed = true }
            else if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
            else { allowed = false }
            guard allowed else { throw SpeechError.microphonePermission }
            try token.checkActive(); try Task.checkCancellation()
            let audio = try await withTaskCancellationHandler {
                try await capture.start(deviceID: deviceID, token: token, update: update)
            } onCancel: { [capture] in token.cancel(); Task { await capture.cancel(token) } }
            try token.checkActive()
            let network = RealtimeTranscriptionSession(socket: OpenAITranscriptionSocket(key: key))
            self.network = network
            transcription = Task { [capture] in
                do {
                    return try await withTaskCancellationHandler { try await network.transcribe(audio, locale: locale, update: update) } onCancel: { Task { await network.close() } }
                } catch {
                    if token.isActive && !(error is CancellationError) { update(.failure(error.localizedDescription)) }
                    token.cancel(); await capture.cancel(token)
                    throw error
                }
            }
        } catch {
            token.cancel(); await capture.cancel(token)
            if self.token === token { self.token = nil }
            throw error
        }
    }
    public func finish() async throws -> String {
        guard let token, let transcription else { throw CancellationError() }
        return try await withTaskCancellationHandler {
            try await capture.finish(token)
            return try await transcription.value
        } onCancel: { [capture, network] in
            token.cancel(); transcription.cancel()
            Task { await capture.cancel(token); await network?.close() }
        }
    }
    public func cancel() {
        guard let token else { return }
        token.cancel(); self.token = nil
        transcription?.cancel(); transcription = nil
        let network = self.network; self.network = nil
        Task { [capture] in await capture.cancel(token); await network?.close() }
    }
}
