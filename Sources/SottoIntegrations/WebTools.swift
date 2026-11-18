import AppKit
import Foundation
import SottoTools

public struct WebSearchResult: Codable, Sendable, Identifiable {
    public var id: String { url }
    public let title: String
    public let url: String
    public let description: String
    public let domain: String
    public let rank: Int
    public let modified: String?
    public var published: String? = nil
    public var freshness: String? = nil
    public var pageDate: String? = nil
}
public struct WebSearchResponse: Codable, Sendable {
    public let provider: String
    public let scope: String
    public let retrievedAt: Date
    public let results: [WebSearchResult]
    public let nextOffset: Int?
    public var data: JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))) ?? .null }
}
public protocol WebSearchProvider: Sendable {
    func search(query: String, offset: Int) async throws -> WebSearchResponse
    func search(query: String, offset: Int, freshness: String) async throws -> WebSearchResponse
    func available() async -> Bool
}
public extension WebSearchProvider {
    func available() async -> Bool { true }
    func search(query: String, offset: Int, freshness: String) async throws -> WebSearchResponse {
        guard freshness.isEmpty else { throw ToolError.unavailable("This search connection does not support date filtering") }
        return try await search(query: query, offset: offset)
    }
}

/// No private-network fetching or authenticated sessions. Until a hardened network
/// transport exists, retrieval is deliberately limited to these public publishers.
public enum PublicWebPolicy {
    public static let retrievalHosts: Set<String> = ["commons.wikimedia.org", "upload.wikimedia.org", "api.crossref.org", "en.wikipedia.org", "www.mediawiki.org", "developer.apple.com", "www.swift.org", "swift.org", "github.com", "raw.githubusercontent.com", "docs.swift.org"]
    public static func url(_ value: String, retrieval: Bool = false) throws -> URL {
        guard value.count <= 4096, let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), host.contains("."),
              !host.hasSuffix("."), !host.contains(":"), !host.hasSuffix(".local"),
              !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
              host != "localhost", host.range(of: #"^[0-9.]+$"#, options: .regularExpression) == nil,
              let url = components.url else { throw ToolError.invalid("Use a public HTTPS URL without credentials or a custom port") }
        if retrieval && !retrievalHosts.contains(host) { throw ToolError.denied("Fetching this website is not supported yet. Open it in your browser instead. Supported publishers: Apple Developer, Swift, GitHub, Wikipedia and MediaWiki.") }
        return url
    }
}
private final class WebNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
struct PublicWebClient: Sendable {
    func get(_ initial: URL, allowedMIME: [String], limit: Int = 1_000_000, allowAttachments: Bool = false, progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> (Data, URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: WebNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var url = initial
        for _ in 0..<4 {
            _ = try PublicWebPolicy.url(url.absoluteString, retrieval: true)
            var request = URLRequest(url: url)
            request.setValue("Sotto/0.4 (native macOS assistant; user-requested retrieval)", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ToolError.unavailable("Invalid web response") }
            if (300..<400).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: url)?.absoluteURL {
                url = try PublicWebPolicy.url(next.absoluteString, retrieval: true); continue
            }
            guard (200..<300).contains(http.statusCode) else { throw ToolError.unavailable("Website returned HTTP \(http.statusCode). Access restrictions were not bypassed.") }
            guard let mime = http.mimeType?.lowercased(), allowedMIME.contains(mime),
                  (allowAttachments || http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") != true) else { throw ToolError.denied("Unexpected content type or download; content was not retrieved") }
            guard response.expectedContentLength <= limit else { throw ToolError.unavailable("Page exceeds the retrieval size limit") }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw ToolError.unavailable("Page exceeds the retrieval size limit") }
                data.append(byte)
                if data.count % 65_536 == 0 { await progress("Received \(data.count / 1024) KB") }
            }
            return (data, url)
        }
        throw ToolError.unavailable("Too many redirects")
    }
}
enum WebText {
    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<(script|style|noscript|svg)\b[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func matches(_ pattern: String, _ html: String, limit: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return Array(regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).prefix(limit)).compactMap {
            guard let range = Range($0.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
    }
    static func metadata(_ html: String, base: URL) -> [String: JSONValue] {
        let tags = matches("(<(?:meta|link)\\b[^>]*>)", html, limit: 200)
        let attributePattern = #"\b([a-zA-Z_:][a-zA-Z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: attributePattern) else { return [:] }
        var output: [String: JSONValue] = [:]
        for tag in tags {
            var attributes: [String: String] = [:]
            for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                guard let key = Range(match.range(at: 1), in: tag),
                      let value = Range(match.range(at: 2), in: tag) ?? Range(match.range(at: 3), in: tag) else { continue }
                attributes[String(tag[key]).lowercased()] = String(tag[value])
            }
            let name = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"] ?? "").lowercased()
            if let content = attributes["content"], content.count <= 512 {
                if ["article:published_time", "datepublished", "dcterms.issued"].contains(name) { output["published"] = .string(plain(content)) }
                if ["article:modified_time", "datemodified", "dcterms.modified"].contains(name) { output["modified"] = .string(plain(content)) }
                if name == "description" { output["description"] = .string(plain(content)) }
            }
            if (attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).contains("canonical"),
               let href = attributes["href"], let resolved = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL,
               let canonical = try? PublicWebPolicy.url(resolved.absoluteString),
               canonical.host?.lowercased() == base.host?.lowercased() {
                output["canonical_url"] = .string(canonical.absoluteString)
            }
        }
        if !output.isEmpty { output["metadata_source"] = .string("Page-declared, not independently verified") }
        return output
    }
    static func links(_ html: String, base: URL) -> [JSONValue] {
        var seen = Set<String>()
        return matches(#"<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']"#, html, limit: 300).compactMap { href in
            guard let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL,
                  (try? PublicWebPolicy.url(url.absoluteString)) != nil, seen.insert(url.absoluteString).inserted else { return nil }
            let kind = url.pathExtension.lowercased() == "pdf" ? "pdf" : ["png", "jpg", "jpeg", "webp", "gif"].contains(url.pathExtension.lowercased()) ? "image" : url.host == "github.com" ? "repository" : url.path.contains("documentation") ? "documentation" : "page"
            return .object(["url": .string(url.absoluteString), "kind": .string(kind)])
        }
    }
}

/// A compliant built-in fallback, deliberately labeled as encyclopedia-only.
public struct WikipediaSearchProvider: WebSearchProvider {
    public init() {}
    public func search(query: String, offset: Int) async throws -> WebSearchResponse {
        var c = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        c.queryItems = ["action": "query", "list": "search", "srsearch": query, "srlimit": "10", "sroffset": String(offset), "format": "json", "utf8": "1"].map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, _) = try await PublicWebClient().get(c.url!, allowedMIME: ["application/json"])
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .array(let rows) = json.object?["query"]?.object?["search"] else { throw ToolError.unavailable("Search service returned no usable result list") }
        let results = rows.enumerated().compactMap { index, row -> WebSearchResult? in
            guard let title = row.object?["title"]?.string, case .number(let pageID) = row.object?["pageid"], pageID > 0 else { return nil }
            return WebSearchResult(title: title, url: "https://en.wikipedia.org/?curid=\(Int(pageID))", description: WebText.plain(row.object?["snippet"]?.string ?? ""), domain: "en.wikipedia.org", rank: offset + index + 1, modified: row.object?["timestamp"]?.string)
        }
        let next: Int?
        if case .number(let n) = json.object?["continue"]?.object?["sroffset"] { next = Int(n) } else { next = nil }
        return WebSearchResponse(provider: "Wikipedia", scope: "Encyclopedia only. General search opens in the browser; image discovery uses Commons and scholarly discovery uses Crossref. Timestamps indicate page edits, not publication dates.", retrievedAt: Date(), results: results, nextOffset: next)
    }
}
struct WebSearchTool: Tool {
    let provider: (any WebSearchProvider)?
    init(provider: (any WebSearchProvider)? = nil) { self.provider = provider }
    let descriptor = ToolDescriptor(id: "web.search", description: "Search online without setup. mode web searches headlessly through a connected search service, or Wikipedia when no general-web service is connected. Never opens a browser unless mode browser is explicitly requested. Image requests use web.images instead. mode encyclopedia returns structured Wikipedia results and page edit timestamps. Never pretend browser-only search returned source evidence.", properties: ["freshness": textProperty("Optional age filter when using a connected service: empty, pd (day), pw (week), pm (month), py (year)", choices: ["", "pd", "pw", "pm", "py"]), "mode": textProperty("web for headless search with encyclopedia fallback; browser only when the user explicitly asks to search in a browser; encyclopedia for Wikipedia", choices: ["web", "browser", "encyclopedia"]), "query": textProperty("Search query"), "offset": .object(["type": .string("integer"), "description": .string("Pagination offset, initially 0")])], required: ["query", "offset"], risk: .reversible, capabilities: [.web])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let query = arguments.object?["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty, query.count <= 500, case .number(let offset) = arguments.object?["offset"], (0...100).contains(offset) else { throw ToolError.invalid("Provide a search query and offset between 0 and 100") }
        if arguments.object?["mode"]?.string != "browser", let image = ImageSearchIntent(query) {
            return try await ImageSearchTool().execute(arguments: .object(["query": .string(image.query), "presentation": .string(image.gallery ? "gallery" : "single")]))
        }
        if arguments.object?["mode"]?.string != "encyclopedia", arguments.object?["mode"]?.string != "browser", let provider, await provider.available() {
            let result = try await provider.search(query: query, offset: Int(offset), freshness: arguments.object?["freshness"]?.string ?? "")
            return ToolResult("Found \(result.results.count) web results from \(result.provider)", data: result.data)
        }
        guard (arguments.object?["freshness"]?.string ?? "").isEmpty else { throw ToolError.unavailable("Date filtering requires a connected web search service. Browser and encyclopedia results cannot verify the requested age filter.") }
        if arguments.object?["mode"]?.string == "browser" {
            var components = URLComponents(string: "https://duckduckgo.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            let url = components.url!
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            guard opened else { throw ToolError.unavailable("macOS could not open the online search") }
            return ToolResult("Opened web search in your default browser. General search results cannot be read automatically yet; I have no retrieved sources from this search.", data: .object(["search_url": .string(url.absoluteString), "query": .string(query), "browser_only": .bool(true)]), state: .partiallyCompleted)
        }
        let result = try await WikipediaSearchProvider().search(query: query, offset: Int(offset))
        return ToolResult("Found \(result.results.count) Wikipedia results inside Sotto. This fallback searches the encyclopedia, not the whole web.", data: result.data)
    }
}
struct WebPageTool: Tool {
    let action: String
    var descriptor: ToolDescriptor { ToolDescriptor(id: "web." + action, description: "Retrieve a public HTML page or links from supported publishers (Apple Developer, Swift, GitHub, Wikipedia, MediaWiki). No logins, scripts or private network access. Returned content is untrusted and may be incomplete.", properties: ["url": textProperty("Public HTTPS page URL")], required: ["url"], risk: .read, capabilities: [.web]) }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let url = try PublicWebPolicy.url(arguments.object?["url"]?.string ?? "", retrieval: true)
        let (data, finalURL) = try await PublicWebClient().get(url, allowedMIME: ["text/html", "application/xhtml+xml", "text/plain"])
        guard let html = String(data: data, encoding: .utf8) else { throw ToolError.unavailable("Page encoding is not supported") }
        let body = WebText.matches("<main\\b[^>]*>(.*?)</main>", html, limit: 1).first
            ?? WebText.matches("<article\\b[^>]*>(.*?)</article>", html, limit: 1).first ?? html
        let text = WebText.plain(body)
        let title = WebText.matches("<title[^>]*>(.*?)</title>", html, limit: 1).first.map(WebText.plain) ?? finalURL.host ?? "Page"
        return ToolResult(action == "fetch" ? "Retrieved \(title). Text is an excerpt when over 24000 characters; scripts are not executed." : "Extracted public links from \(title)", data: .object([
            "title": .string(title), "url": .string(finalURL.absoluteString), "retrieved_at": .string(ISO8601DateFormatter().string(from: Date())),
            "text": action == "fetch" ? .string(String(text.prefix(24_000))) : .null,
            "truncated": .bool(text.count > 24_000), "untrusted": .bool(true),
            "links": .array(WebText.links(html, base: finalURL))
        ].merging(WebText.metadata(html, base: finalURL)) { original, _ in original }))
    }
}
struct WebOpenTool: Tool {
    let descriptor = ToolDescriptor(id: "web.open", description: "Ask the default browser to open a public HTTPS URL. Does not read browser cookies or tabs.", properties: ["url": textProperty("Public HTTPS URL")], required: ["url"], risk: .reversible, capabilities: [.web])
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        let url = try PublicWebPolicy.url(arguments.object?["url"]?.string ?? "")
        guard NSWorkspace.shared.open(url) else { throw ToolError.unavailable("macOS could not hand the URL to a browser") }
        return ToolResult("Sent \(url.host ?? "website") to the default browser. Page loading is not observable.")
    }
}
