import Foundation

public struct SpeechTranscript: Sendable, Equatable {
    public let confirmed: String
    public let provisional: String
    public var text: String { confirmed + provisional }
    public init(confirmed: String = "", provisional: String = "") { self.confirmed = confirmed; self.provisional = provisional }
}

/// SpeechAnalyzer ranges identify revisions. A volatile replacement must not
/// be appended to its predecessor, nor overwrite already finalized speech.
struct StreamingTranscript {
    struct Segment { let start: Double; let end: Double; let text: String; let final: Bool }
    private var segments: [Segment] = []
    mutating func receive(text: String, start: Double, end: Double, final: Bool) {
        guard start.isFinite, end.isFinite, start >= 0, end >= start else { return }
        func overlaps(_ segment: Segment) -> Bool {
            segment.start == start || (segment.start < end && segment.end > start)
        }
        if !final && segments.contains(where: { $0.final && overlaps($0) }) { return }
        segments.removeAll { overlaps($0) }
        segments.append(Segment(start: start, end: end, text: text, final: final))
        segments.sort { $0.start < $1.start }
    }
    private func joined(_ values: [Segment]) -> String {
        values.map(\.text).reduce("") { result, piece in
            guard !result.isEmpty, !piece.isEmpty else { return result + piece }
            if result.last?.isWhitespace == true || piece.first?.isWhitespace == true || ",.!?;:".contains(piece.first!) { return result + piece }
            return result + " " + piece
        }
    }
    var snapshot: SpeechTranscript {
        let confirmed = joined(segments.filter(\.final))
        let live = joined(segments.filter { !$0.final })
        let separator = !confirmed.isEmpty && !live.isEmpty && confirmed.last?.isWhitespace != true && live.first?.isWhitespace != true ? " " : ""
        return SpeechTranscript(confirmed: confirmed, provisional: separator + live)
    }
}
