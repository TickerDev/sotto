import Foundation

public struct VoiceLatencyTrace: Sendable {
    public enum Phase: String, Sendable { case microphoneReady, firstPartial, inputEnded, finalTranscript, firstAction, verifiedCompletion }
    public let id = UUID()
    public let started: Double
    private var times: [Phase: Double] = [:]
    public init(started: Double) { self.started = started }
    @discardableResult public mutating func record(_ phase: Phase, at time: Double) -> Bool {
        guard times[phase] == nil || phase == .verifiedCompletion else { return false }
        times[phase] = max(started, time); return true
    }
    public var milliseconds: [String: Double] {
        var result: [String: Double] = [:]
        for phase in [Phase.microphoneReady, .firstPartial, .firstAction, .verifiedCompletion] {
            if let time = times[phase] { result["activationTo\(phase.rawValue.prefix(1).uppercased())\(phase.rawValue.dropFirst())Ms"] = (time - started) * 1000 }
        }
        if let end = times[.inputEnded], let final = times[.finalTranscript] { result["inputEndToFinalMs"] = max(0, final - end) * 1000 }
        if let mic = times[.microphoneReady], let first = times[.firstPartial] { result["microphoneToFirstPartialMs"] = max(0, first - mic) * 1000 }
        if let end = times[.inputEnded] {
            if let action = times[.firstAction] { result["inputEndToFirstActionMs"] = max(0, action - end) * 1000 }
            if let completion = times[.verifiedCompletion] { result["inputEndToVerifiedCompletionMs"] = max(0, completion - end) * 1000 }
        }
        if let final = times[.finalTranscript], let action = times[.firstAction] {
            result["finalTranscriptToFirstActionMs"] = max(0, action - final) * 1000
        }
        return result
    }
}
