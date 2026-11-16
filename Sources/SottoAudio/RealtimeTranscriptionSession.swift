import Foundation

protocol TranscriptionSocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

private final class TranscriptionNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

actor OpenAITranscriptionSocket: TranscriptionSocket {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    init(key: String) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 75
        config.httpShouldSetCookies = false; config.urlCache = nil
        session = URLSession(configuration: config, delegate: TranscriptionNoRedirect(), delegateQueue: nil)
        var request = URLRequest(url: RealtimeTranscriptionWire.endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 262_144
        socket.resume()
    }
    func send(_ data: Data) async throws {
        guard let text = String(data: data, encoding: .utf8) else { throw SpeechError.message("Invalid transcription request.") }
        try await socket.send(.string(text))
    }
    func receive() async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): return Data(text.utf8)
        case .data(let data): return data
        @unknown default: throw SpeechError.message("Unexpected transcription message.")
        }
    }
    func close() { socket.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
}

actor RealtimeTranscriptionSession {
    private let socket: any TranscriptionSocket
    private var state = RealtimeTranscriptState()
    private var failure: Error?
    private var readyWaiter: CheckedContinuation<Void, Error>?
    private var finalWaiter: CheckedContinuation<String, Error>?
    private var receiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private let connectionTimeout: Duration
    private let finalTimeout: Duration
    init(socket: any TranscriptionSocket, connectionTimeout: Duration = .seconds(10), finalTimeout: Duration = .seconds(15)) {
        self.socket = socket; self.connectionTimeout = connectionTimeout; self.finalTimeout = finalTimeout
    }

    func transcribe(_ audio: AsyncThrowingStream<Data, Error>, locale: String, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws -> String {
        try await withTaskCancellationHandler {
            try await run(audio, locale: locale, update: update)
        } onCancel: { Task { await self.close() } }
    }
    private func run(_ audio: AsyncThrowingStream<Data, Error>, locale: String, update: @escaping @Sendable (SpeechUpdate) -> Void) async throws -> String {
        receiver = Task { [weak self] in await self?.receive(update: update) }
        armDeadline(connectionTimeout, message: "OpenAI transcription couldn’t connect in time. Try again.")
        do {
            try Task.checkCancellation()
            try await socket.send(RealtimeTranscriptionWire.configure(locale: locale))
            if !state.ready { try await withCheckedThrowingContinuation { readyWaiter = $0; resolve() } }
            deadline?.cancel(); deadline = nil
            var total = 0
            for try await data in audio {
                try Task.checkCancellation()
                if let failure { throw failure }
                total += data.count
                guard total <= 2_880_000 else { throw SpeechError.message("Recording exceeded the transcription audio limit.") }
                try await socket.send(RealtimeTranscriptionWire.append(data))
            }
            try Task.checkCancellation()
            if let failure { throw failure }
            // The service requires at least 100 ms of audio. Do not pad or
            // manufacture silence for a tap that contained no usable speech.
            guard total >= 4_800 else { throw SpeechError.message("Recording was too short. Hold the shortcut and try again.") }
            armDeadline(finalTimeout, message: "OpenAI transcription timed out. The recording was discarded.")
            try await socket.send(RealtimeTranscriptionWire.commit())
            let text = try await withCheckedThrowingContinuation { finalWaiter = $0; resolve() }
            try Task.checkCancellation()
            await close()
            return text
        } catch {
            await close()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if error is URLError { throw SpeechError.message("Couldn’t connect to OpenAI transcription. Check your connection and API key, then try again.") }
            throw error
        }
    }
    private func receive(update: @escaping @Sendable (SpeechUpdate) -> Void) async {
        do {
            while !Task.isCancelled {
                let data = try await socket.receive()
                if let text = try state.consume(data) { update(.transcript(text)) }
                resolve()
            }
        } catch { fail(error) }
    }
    private func resolve() {
        if let failure {
            readyWaiter?.resume(throwing: failure); readyWaiter = nil
            finalWaiter?.resume(throwing: failure); finalWaiter = nil
        } else {
            if state.ready { readyWaiter?.resume(); readyWaiter = nil }
            if let text = state.final { finalWaiter?.resume(returning: text); finalWaiter = nil }
        }
    }
    private func fail(_ error: Error) { if failure == nil { failure = error }; resolve() }
    private func armDeadline(_ duration: Duration, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            await self.expire(message)
        }
    }
    private func expire(_ message: String) async { fail(SpeechError.message(message)); await socket.close() }
    func close() async {
        deadline?.cancel(); deadline = nil; receiver?.cancel(); receiver = nil
        fail(CancellationError()); await socket.close()
    }
}
