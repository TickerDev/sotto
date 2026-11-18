import Foundation
import SottoAgent
import SottoIntegrations
import SottoTools

/// Exact ordinal commands use actual current tool results, never model-authored URLs.
enum WebResultFollowup {
    static func action(_ request: String, results: [WebSearchResult]) -> NativeCommandProvider? {
        let text = request.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let ordinals = ["first": 0, "second": 1, "third": 2, "fourth": 3, "fifth": 4]
        for (word, index) in ordinals {
            guard ["open the \(word) search result", "open \(word) search result", "open the \(word) web result"].contains(text),
                  results.indices.contains(index), (try? PublicWebPolicy.url(results[index].url)) != nil else { continue }
            return .toolAction(name: "web.open", arguments: .object(["url": .string(results[index].url)]))
        }
        return nil
    }
}
