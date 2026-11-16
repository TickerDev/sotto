import Foundation

public enum SpeechBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, openAIRealtime
    public var id: String { rawValue }
    public var name: String { self == .apple ? "Apple Speech" : "OpenAI Realtime" }
}

enum RealtimeTranscriptionWire {
    static let endpoint = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
    static let model = "gpt-live-transcribe"
    static func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    static func configure(locale: String) throws -> Data {
        let language = Locale(identifier: locale).language.languageCode?.identifier ?? "en"
        guard ["en", "es", "fr", "de", "he"].contains(language) else {
            throw SpeechError.message("Choose a supported transcription language in Voice settings.")
        }
        return try json(["type": "session.update", "session": ["type": "transcription", "audio": ["input": [
            "format": ["type": "audio/pcm", "rate": 24000],
            "transcription": ["model": model, "languages": [language], "delay": "low"],
            "turn_detection": NSNull()
        ]]]])
    }
    static func append(_ pcm: Data) throws -> Data {
        guard !pcm.isEmpty, pcm.count % 2 == 0, pcm.count <= 131_072 else { throw SpeechError.message("Invalid transcription audio buffer.") }
        return try json(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
    }
    static func commit() throws -> Data { try json(["type": "input_audio_buffer.commit"]) }
}

/// A single explicit recording is one committed turn. Never accept a final
/// transcript from another item, or use an uncommitted partial as a command.
struct RealtimeTranscriptState: Sendable {
    var ready = false
    var committed: String?
    private var partials: [String: String] = [:]
    private var finals: [String: String] = [:]
    var final: String? { committed.flatMap { finals[$0] } }
    mutating func consume(_ data: Data) throws -> String? {
        guard data.count <= 262_144,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else {
            throw SpeechError.message("OpenAI returned an invalid transcription event.")
        }
        switch type {
        case "session.updated":
            guard let session = object["session"] as? [String: Any], session["type"] as? String == "transcription" else {
                throw SpeechError.message("OpenAI did not confirm a transcription session.")
            }
            ready = true
        case "input_audio_buffer.committed":
            guard committed == nil, let id = object["item_id"] as? String, !id.isEmpty else { throw SpeechError.message("OpenAI returned an invalid audio commit.") }
            committed = id
        case "conversation.item.input_audio_transcription.delta", "conversation.item.input_audio_transcription.completed":
            guard let id = object["item_id"] as? String, !id.isEmpty, id.count < 256 else { throw SpeechError.message("OpenAI returned an invalid transcript item.") }
            if committed != nil && committed != id { return nil }
            guard partials[id] != nil || finals[id] != nil || Set(partials.keys).union(finals.keys).count < 4 else { throw SpeechError.message("OpenAI returned too many transcription items.") }
            if type.hasSuffix(".delta") {
                guard let delta = object["delta"] as? String else { throw SpeechError.message("OpenAI returned an invalid transcript delta.") }
                let text = (partials[id] ?? "") + delta
                guard text.utf8.count <= 65_536 else { throw SpeechError.message("Transcription exceeded its text limit.") }
                partials[id] = text
                return text
            }
            guard let text = object["transcript"] as? String, text.utf8.count <= 65_536 else { throw SpeechError.message("OpenAI returned an invalid final transcript.") }
            finals[id] = text
        case "conversation.item.input_audio_transcription.failed", "error":
            if let id = object["item_id"] as? String, let committed, id != committed { return nil }
            let error = object["error"] as? [String: Any]
            let code = error?["code"] as? String ?? ""
            if ["invalid_api_key", "authentication_error"].contains(code) { throw SpeechError.message("OpenAI couldn’t authenticate transcription. Check your API key in Voice settings.") }
            if code == "insufficient_quota" || code == "rate_limit_exceeded" { throw SpeechError.message("OpenAI transcription reached an account or rate limit. Check API billing or try again later.") }
            // Do not surface raw server messages, which may contain user audio text.
            throw SpeechError.message("OpenAI couldn’t transcribe this recording. Check model access and your connection, then try again.")
        default: break
        }
        return nil
    }
}
