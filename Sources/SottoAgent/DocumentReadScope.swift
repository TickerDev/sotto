import Foundation
import SottoTools

/// Only actual search results from this request (not model-authored messages)
/// or a path literally supplied by the user or an explicitly named approved file alias may authorize a document read.
struct DocumentReadScope {
    static func explicitSummaryArguments(_ request: String) -> JSONValue? {
        let pattern = #"^(?:read and )?summarize(?: this (?:document|file)(?: in one sentence)?:)?\s+((?:/|~/).+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: request, range: NSRange(request.startIndex..., in: request)),
              let range = Range(match.range(at: 1), in: request) else { return nil }
        let path = String(request[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.contains("\n"), !path.lowercased().contains(" and "), !path.lowercased().contains(" then "),
              DocumentTextFormats.supports(path) else { return nil }
        return .object(["path": .string(path)])
    }
    private var paths: Set<String> = []
    mutating func recordSearch(_ result: ToolResult) {
        guard let files = FileSearchResults.decode(result.data)?.files else { return }
        for file in files.prefix(20) { if let path = canonical(file.path) { paths.insert(path) } }
    }
    mutating func recordAliases(_ result: ToolResult, request: String) {
        guard result.state == .success, case .array(let aliases) = result.data else { return }
        let normalizedRequest = request.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        for alias in aliases.prefix(100) {
            guard alias.object?["kind"]?.string == "file",
                  let name = alias.object?["name"]?.string, !name.isEmpty,
                  let target = alias.object?["path"]?.string, let path = canonical(target) else { continue }
            let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            let variants = normalized.hasPrefix("my ") ? [normalized, String(normalized.dropFirst(3))] : [normalized]
            if variants.contains(where: { value in
                let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: value) + #"(?![\p{L}\p{N}_])"#
                return normalizedRequest.range(of: pattern, options: .regularExpression) != nil
            }) { paths.insert(path) }
        }
    }
    func validate(_ arguments: JSONValue, request: String) throws {
        guard let raw = arguments.object?["path"]?.string, let path = canonical(raw), paths.contains(path) || literalPath(raw, in: request) else {
            throw ToolError.denied("Find the requested document first, or ask the user for its exact path. A model-invented path cannot be read.")
        }
    }
    private func literalPath(_ path: String, in request: String) -> Bool {
        guard let range = request.range(of: path) else { return false }
        let before = range.lowerBound == request.startIndex ? nil : request[request.index(before: range.lowerBound)]
        let after = range.upperBound == request.endIndex ? nil : request[range.upperBound]
        return (before == nil || before!.isWhitespace || "\"'`([".contains(before!)) &&
            (after == nil || after!.isWhitespace || "\"'`)]".contains(after!))
    }
    private func canonical(_ path: String) -> String? {
        guard !path.contains("\0"), path.hasPrefix("/") || path.hasPrefix("~/") else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
