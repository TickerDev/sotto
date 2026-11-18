import Foundation
import SottoTools

/// A bounded filename-only fallback when Spotlight supplies no useful matches.
/// This uses ordinary macOS file access; denial is never bypassed.
actor DocumentFolderSearch {
    let roots: [URL]
    init(roots: [URL]? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.roots = roots ?? ["Documents", "Desktop", "Downloads", "Library/Mobile Documents/com~apple~CloudDocs", "Library/CloudStorage"].map { home.appendingPathComponent($0) }
    }
    func search(_ query: String) async throws -> [FileSearchMatch] {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey]
        let terms = FileSearchRanking.terms(query).map(FileSearchRanking.normalized)
        var matches: [FileSearchMatch] = []
        var inspected = 0
        for root in roots {
            try Task.checkCancellation()
            if DocumentSearchPrivacy.isExcluded(root) { continue }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if DocumentSearchPrivacy.isExcluded(url) { enumerator.skipDescendants(); continue }
                inspected += 1
                guard inspected <= 5_000 else { return Array(FileSearchRanking.ranked(matches, query: query).prefix(20)) }
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isDirectory == true {
                    if enumerator.level >= 6 || values.isPackage == true || ["node_modules", "build", "target", "Library"].contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    if values.isPackage != true { continue }
                }
                let name = FileSearchRanking.normalized(url.lastPathComponent)
                if terms.contains(where: name.contains) { matches.append(FileSearchMatch(path: url.path, modified: values.contentModificationDate)) }
            }
        }
        try Task.checkCancellation()
        return Array(FileSearchRanking.ranked(matches, query: query).prefix(20))
    }
}

enum DocumentSearchPrivacy {
    static func isExcluded(_ url: URL) -> Bool {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
        return (UserDefaults.standard.stringArray(forKey: "documentSearchExcludedPaths") ?? []).contains {
            let root = URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).resolvingSymlinksInPath().standardizedFileURL.path
            return canonical == root || canonical.hasPrefix(root == "/" ? "/" : root + "/")
        }
    }
}
