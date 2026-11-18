import Foundation
import SottoTools

/// Credentials are supplied by the application, never tool arguments or preferences.
public struct BraveSearchProvider: WebSearchProvider {
    private let key: @Sendable () async throws -> String?
    private let enabled: @Sendable () -> Bool
    private let transport: @Sendable (URLRequest) async throws -> Data
    public init(key: @escaping @Sendable () async throws -> String?, enabled: @escaping @Sendable () -> Bool = { true }) {
        self.init(key: key, enabled: enabled, transport: Self.retrieve)
    }
    init(key: @escaping @Sendable () async throws -> String?, enabled: @escaping @Sendable () -> Bool = { true }, transport: @escaping @Sendable (URLRequest) async throws -> Data) {
        self.key = key; self.enabled = enabled; self.transport = transport
    }
    public func available() async -> Bool { enabled() }
    public func search(query: String, offset: Int) async throws -> WebSearchResponse {
        try await search(query: query, offset: offset, freshness: "")
    }
    public func search(query: String, offset: Int, freshness: String) async throws -> WebSearchResponse {
        try Task.checkCancellation()
        guard enabled() else { throw ToolError.unavailable("Web answers are not connected. Browser search is still available.") }
        guard let credential = try await key(), !credential.isEmpty else { throw ToolError.denied("Reconnect web answers in Sotto’s Web settings.") }
        let request = try Self.request(query: query, offset: offset, freshness: freshness, key: credential)
        let data = try await transport(request)
        try Task.checkCancellation()
        return try Self.parse(data, offset: offset, freshness: freshness)
    }
    static func request(query: String, offset: Int, freshness: String, key: String) throws -> URLRequest {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 500,
              query.split(whereSeparator: \.isWhitespace).count <= 75,
              (0...9).contains(offset), ["", "pd", "pw", "pm", "py"].contains(freshness),
              !key.isEmpty, key.utf8.count <= 4096, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw ToolError.invalid("Invalid search query, page, age filter or search credential") }
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "text_decorations", value: "false"),
            URLQueryItem(name: "result_filter", value: "web"), URLQueryItem(name: "safesearch", value: "moderate")
        ]
        if !freshness.isEmpty { components.queryItems?.append(URLQueryItem(name: "freshness", value: freshness)) }
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    static func parse(_ data: Data, offset: Int, freshness: String) throws -> WebSearchResponse {
        guard data.count <= 1_000_000 else { throw ToolError.unavailable("Search response exceeded its size limit") }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard value.object?["error"] == nil else { throw ToolError.unavailable("Search service reported an error") }
        let rows: [JSONValue]
        if case .array(let results) = value.object?["web"]?.object?["results"] { rows = results }
        else if value.object?["query"]?.object?["more_results_available"] == .bool(false) { rows = [] }
        else { throw ToolError.unavailable("Search service returned invalid results") }
        var seen = Set<String>()
        let results = rows.prefix(20).enumerated().compactMap { index, row -> WebSearchResult? in
            guard let object = row.object, let title = object["title"]?.string,
                  let raw = object["url"]?.string, let url = try? PublicWebPolicy.url(raw),
                  seen.insert(url.absoluteString).inserted else { return nil }
            return WebSearchResult(title: String(WebText.plain(title).prefix(512)), url: url.absoluteString,
                description: String(WebText.plain(object["description"]?.string ?? "").prefix(2000)),
                domain: url.host ?? "", rank: offset * 10 + index + 1, modified: nil,
                freshness: object["age"]?.string, pageDate: object["page_age"]?.string)
        }
        let more = value.object?["query"]?.object?["more_results_available"] == .bool(true)
        return WebSearchResponse(provider: "Brave Search", scope: "Public web search. Dates and snippets are provider-reported, not independently verified. Age filter: \(freshness.isEmpty ? "any" : freshness).", retrievedAt: Date(), results: results, nextOffset: more && offset < 9 ? offset + 1 : nil)
    }
    private static func retrieve(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        try await SearchRequestBudget.shared.reserve()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: SearchNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ToolError.unavailable("Invalid search service response") }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw ToolError.denied("The web search connection was rejected. Check its access key and plan in Web settings.")
        case 429: throw ToolError.unavailable("The web search usage limit was reached. Check the service’s account limits.")
        default: throw ToolError.unavailable("Web search failed (HTTP \(http.statusCode)). No results were retrieved.")
        }
        guard http.mimeType == "application/json", response.expectedContentLength <= 1_000_000 else { throw ToolError.unavailable("Invalid or oversized search response") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_000_000 else { throw ToolError.unavailable("Search response exceeded its size limit") }
            data.append(byte)
        }
        return data
    }
}
private final class SearchNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward the subscription token to a redirected host.
        completionHandler(nil)
    }
}

/// Counts attempted paid requests before dispatch. No queries or credentials persist.
/// Conservative failures count too; other applications' usage is outside this limit.
actor SearchRequestBudget {
    static let shared = SearchRequestBudget()
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults; self.now = now
    }
    func reserve() throws {
        let day = Int(now().timeIntervalSince1970 / 86_400)
        let oldDay = defaults.integer(forKey: "webSearchUsageDay")
        let count = oldDay == day ? defaults.integer(forKey: "webSearchUsageCount") : 0
        let configured = defaults.integer(forKey: "webSearchDailyLimit")
        let limit = configured == 0 ? 50 : min(500, max(1, configured))
        guard count < limit else { throw ToolError.denied("This Mac’s daily web search limit was reached. Review the limit in Web settings, or use browser search explicitly.") }
        defaults.set(day, forKey: "webSearchUsageDay")
        defaults.set(count + 1, forKey: "webSearchUsageCount")
    }
}
