import Foundation
import SottoTools

/// Evidence collection only. Reasoning synthesizes these records with their exact
/// citations; neither snippets nor webpages can authorize subsequent local actions.
struct ResearchTool: Tool {
    let provider: (any WebSearchProvider)?
    let fetch: @Sendable (String) async throws -> ToolResult
    init(provider: (any WebSearchProvider)? = nil) {
        self.init(provider: provider, fetch: { try await WebPageTool(action: "fetch").execute(arguments: .object(["url": .string($0)])) })
    }
    init(provider: (any WebSearchProvider)?, fetch: @escaping @Sendable (String) async throws -> ToolResult) {
        self.provider = provider; self.fetch = fetch
    }
    let descriptor = ToolDescriptor(id: "web.research", description: "Collect bounded cited evidence for comparison. Provide up to 3 explicit public source URLs, or a question to discover sources through connected web search (Wikipedia fallback). Up to 2 searches and 3 page fetches, 24000 text characters total. Labels snippets, inaccessible sources and provider-reported dates. Never claim publisher diversity establishes independent verification.", properties: [
        "query": textProperty("Research question"),
        "urls": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "maxItems": .number(3), "description": .string("Optional exact sources explicitly selected by the user; empty to discover sources")]),
        "freshness": textProperty("Optional connected-search age filter", choices: ["", "pd", "pw", "pm", "py"])
    ], required: ["query"], risk: .read, capabilities: [.web], timeoutSeconds: 90)
    func execute(arguments: JSONValue) async throws -> ToolResult { try await execute(arguments: arguments, progress: { _ in }) }
    func execute(arguments: JSONValue, progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        let query = arguments.object?["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty, query.count <= 500 else { throw ToolError.invalid("Provide a research question under 500 characters") }
        let freshness = arguments.object?["freshness"]?.string ?? ""
        let deadline = ContinuousClock.now.advanced(by: .seconds(85))
        var candidates: [WebSearchResult] = []
        var searchQueries: [JSONValue] = []
        var seen = Set<String>()
        let explicit: Bool
        if case .array(let urls) = arguments.object?["urls"], !urls.isEmpty {
            guard urls.count <= 3 else { throw ToolError.invalid("Choose at most three sources") }
            explicit = true
            // Validate all explicit URLs before any network request.
            for raw in urls {
                guard let value = raw.string else { throw ToolError.invalid("Source URLs must be text") }
                let url = try PublicWebPolicy.url(value)
                let canonical = Self.identity(url)
                if seen.insert(canonical).inserted {
                    candidates.append(WebSearchResult(title: url.host ?? "Source", url: url.absoluteString, description: "", domain: url.host ?? "", rank: candidates.count + 1, modified: nil))
                }
            }
        } else {
            explicit = false
            let search: any WebSearchProvider
            if let provider, await provider.available() { search = provider } else { search = WikipediaSearchProvider() }
            let queries = [query, String((query + " evidence").prefix(500))]
            for searchQuery in queries {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { break }
                await progress("Finding research sources")
                let response = try await search.search(query: searchQuery, offset: 0, freshness: freshness)
                searchQueries.append(.object(["query": .string(searchQuery), "provider": .string(response.provider), "scope": .string(response.scope)]))
                for candidate in response.results {
                    guard let url = try? PublicWebPolicy.url(candidate.url), seen.insert(Self.identity(url)).inserted else { continue }
                    candidates.append(candidate)
                }
                if Set(candidates.map { Self.publisher($0.domain) }).count >= 3 { break }
            }
            // Prefer relevance first within each publisher, then fill remaining slots.
            var publishers = Set<String>()
            let diverse = candidates.filter { publishers.insert(Self.publisher($0.domain)).inserted }
            let selected = Set(diverse.prefix(3).map(\.url))
            candidates = Array((Array(diverse.prefix(3)) + candidates.filter { !selected.contains($0.url) }).prefix(3))
        }
        var sources: [JSONValue] = []
        var failures: [JSONValue] = []
        var finalURLs = Set<String>()
        var characters = 0
        var fetchedPages = 0
        for candidate in candidates.prefix(3) {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { break }
            await progress("Reading source \(sources.count + 1) of \(min(3, candidates.count))")
            do {
                let result = try await fetch(candidate.url)
                guard result.state == .success || result.state == .partiallyCompleted,
                      let object = result.data.object, let raw = object["url"]?.string,
                      let finalURL = try? PublicWebPolicy.url(raw), let text = object["text"]?.string,
                      !text.isEmpty else { throw ToolError.unavailable("Source returned no readable page text") }
                guard finalURLs.insert(Self.identity(finalURL)).inserted else { continue }
                let excerpt = String(text.prefix(min(8000, max(0, 24_000 - characters))))
                characters += excerpt.count; fetchedPages += 1
                let publisher = Self.publisher(finalURL.host ?? "")
                sources.append(.object([
                    "citation": .string("S\(sources.count + 1)"), "url": .string(finalURL.absoluteString),
                    "title": object["title"] ?? .string(candidate.title), "text": .string(excerpt),
                    "publisher_group": .string(publisher), "evidence_kind": .string("page_excerpt"),
                    "published": object["published"] ?? .null, "modified": object["modified"] ?? .null,
                    "retrieved_at": .string(ISO8601DateFormatter().string(from: Date())),
                    "relevance_score": .number(Self.relevance(query, title: object["title"]?.string ?? candidate.title, text: excerpt)),
                    "truncated": .bool(object["truncated"] == .bool(true) || excerpt.count < text.count),
                    "untrusted": .bool(true)
                ]))
            } catch is CancellationError { throw CancellationError() }
            catch {
                failures.append(.object(["url": .string(candidate.url), "error": .string(error.localizedDescription)]))
                // Search snippets are genuine evidence, but must never masquerade as page reads.
                if !explicit, !candidate.description.isEmpty {
                    sources.append(.object([
                        "citation": .string("S\(sources.count + 1)"), "url": .string(candidate.url),
                        "title": .string(candidate.title), "text": .string(String(candidate.description.prefix(2000))),
                        "publisher_group": .string(Self.publisher(candidate.domain)), "evidence_kind": .string("search_snippet"),
                        "published": candidate.published.map(JSONValue.string) ?? .null,
                        "reported_page_date": candidate.pageDate.map(JSONValue.string) ?? .null,
                        "freshness": candidate.freshness.map(JSONValue.string) ?? .null,
                        "relevance_score": .number(Self.relevance(query, title: candidate.title, text: candidate.description)),
                        "untrusted": .bool(true)
                    ]))
                }
            }
        }
        let groups = Set(sources.compactMap { $0.object?["publisher_group"]?.string })
        let partial = !failures.isEmpty || sources.count < candidates.count || sources.isEmpty
        return ToolResult("Collected \(sources.count) cited sources (\(fetchedPages) page excerpts, \(groups.count) publisher groups). Compare claims and disagreements using only this evidence. Publisher diversity is not proof of independence; unknown dates must remain unknown.", data: .object([
            "query": .string(query), "sources": .array(sources), "failures": .array(failures),
            "searches": .array(searchQueries), "page_fetches": .number(Double(fetchedPages)),
            "publisher_groups": .number(Double(groups.count)), "characters": .number(Double(characters)),
            "uncertainty": .array([.string("Search rank and lexical relevance are not fact verification."), .string("Sources may share underlying evidence or omit relevant findings."), .string("Publication and modification dates may be missing or provider-reported.")]),
            "untrusted": .bool(true)
        ]), state: partial ? .partiallyCompleted : .success)
    }
    static func identity(_ url: URL) -> String {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: true)
        c?.fragment = nil
        return c?.url?.absoluteString ?? url.absoluteString
    }
    static func publisher(_ host: String) -> String {
        let host = host.lowercased()
        for family in ["wikipedia.org", "wikimedia.org", "apple.com", "swift.org", "github.com", "githubusercontent.com", "crossref.org"] {
            if host == family || host.hasSuffix("." + family) { return family == "githubusercontent.com" ? "github.com" : family }
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    static func relevance(_ query: String, title: String, text: String) -> Double {
        let ignored: Set<String> = ["the", "and", "for", "with", "from", "about", "what", "how", "compare", "evidence"]
        let terms = Set(query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 && !ignored.contains($0) })
        guard !terms.isEmpty else { return 0 }
        let haystack = (title + " " + text).lowercased()
        return Double(terms.filter { haystack.contains($0) }.count) / Double(terms.count)
    }
}
