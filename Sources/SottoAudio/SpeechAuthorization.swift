@preconcurrency import Speech

/// Speech's legacy Objective-C callback can arrive on any queue. Keep it outside
/// MainActor and pass only the Sendable status through the continuation.
public enum SpeechAuthorization {
    public typealias Request = @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void

    nonisolated public static func request(using request: Request = { reply in
        SFSpeechRecognizer.requestAuthorization { @Sendable status in reply(status) }
    }) async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            request { @Sendable status in continuation.resume(returning: status) }
        }
    }
}
