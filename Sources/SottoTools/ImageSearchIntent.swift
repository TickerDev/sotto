import Foundation

/// Bounded routing for image discovery, not generation, local photos or compound actions.
public struct ImageSearchIntent: Sendable {
    public let query: String
    public let gallery: Bool
    public init?(_ request: String) {
        let text = request.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard text.count <= 600,
              text.range(of: #"\b(generate|draw|create|make|edit|replace|attached|uploaded|selected|screenshot)\b|\bmy\b|\bon (?:the|this) mac\b|\b(?:and|then)\s+(?:open|delete|download|send|move|rename|set|run|quit|find|show|search)\b"#, options: .regularExpression) == nil else { return nil }
        let patterns = [
            #"^(?:please )?(?:show(?: me)?|find(?: me)?|search(?: the web| online)? for|get(?: me)?|look for) (?:an? |some )?(pictures?|photos?|images?)(?: online)? (?:of |for )(.+?)(?: online)?$"#,
            #"^(?:please )?(?:show(?: me)?|find(?: me)?|search(?: the web| online)? for|get(?: me)?) (?:an? )?(.+?) (pictures?|photos?|images?)(?: online)?$"#,
            #"^(?:an? )?(.+?) (picture|photo|image)$"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let subject = Range(match.range(at: index == 0 ? 2 : 1), in: text),
                  let kind = Range(match.range(at: index == 0 ? 1 : 2), in: text) else { continue }
            let query = String(text[subject]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, query.count <= 500 else { return nil }
            self.query = query
            self.gallery = text[kind].hasSuffix("s")
            return
        }
        return nil
    }
}
