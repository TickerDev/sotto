import Foundation
import SottoTools

enum FileSearchRanking {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func terms(_ query: String) -> [String] {
        ["resume", "cv", "curriculum vitae"].contains(normalized(query)) ? ["resume", "cv", "curriculum vitae"] : [query]
    }
    static func ranked(_ candidates: [FileSearchMatch], query: String) -> [FileSearchMatch] {
        let resume = terms(query).count > 1
        let documentTypes = ["pdf", "doc", "docx", "pages", "rtf", "txt", "odt"]
        let filtered = candidates.filter { match in
            guard resume else { return true }
            let url = URL(fileURLWithPath: match.path)
            let name = normalized(url.deletingPathExtension().lastPathComponent)
            let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            let cloudDocument = match.path.contains("/Library/Mobile Documents/") || match.path.contains("/Library/CloudStorage/")
            let libraryNoise = match.path.contains("/Library/") && !cloudDocument
            let resumeName = words.contains("resume") || words.contains("cv") || name.contains("curriculum vitae") || (url.pathExtension.lowercased() != "txt" && name.contains("resume"))
            return documentTypes.contains(url.pathExtension.lowercased()) && resumeName && !libraryNoise &&
                !["/node_modules/", "/.build/", "/.git/"].contains(where: match.path.contains)
        }
        func score(_ match: FileSearchMatch) -> Int {
            if query == ".pdf" { return 0 } // Explicit latest-PDF requests sort by date.
            let url = URL(fileURLWithPath: match.path)
            let name = normalized(url.deletingPathExtension().lastPathComponent)
            var value = name == normalized(query) ? 60 : 0
            if documentTypes.contains(url.pathExtension.lowercased()) { value += 20 }
            if url.pathExtension.lowercased() == "pdf" { value += 10 }
            if match.path.contains("/Documents/") || match.path.contains("/Desktop/") || match.path.contains("/Downloads/") { value += 15 }
            return value
        }
        var seen = Set<String>()
        return filtered.filter { seen.insert($0.path).inserted }.sorted {
            if score($0) != score($1) { return score($0) > score($1) }
            if $0.modified != $1.modified { return ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            return $0.path < $1.path
        }
    }
}
