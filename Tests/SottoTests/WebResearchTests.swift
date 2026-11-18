import XCTest
@testable import SottoIntegrations
@testable import SottoTools

private actor SearchRequests {
    var values: [URLRequest] = []
    func add(_ value: URLRequest) { values.append(value) }
}
private struct ResearchSearchFixture: WebSearchProvider {
    func search(query: String, offset: Int) async throws -> WebSearchResponse {
        WebSearchResponse(provider: "Fixture", scope: "Controlled metadata", retrievedAt: Date(), results: [
            WebSearchResult(title: "Swift concurrency", url: "https://www.swift.org/concurrency", description: "Swift concurrency overview", domain: "www.swift.org", rank: 1, modified: nil),
            WebSearchResult(title: "Apple concurrency", url: "https://developer.apple.com/concurrency", description: "Concurrency on Apple platforms", domain: "developer.apple.com", rank: 2, modified: nil),
            WebSearchResult(title: "Runtime source", url: "https://github.com/swiftlang/swift", description: "Swift runtime", domain: "github.com", rank: 3, modified: nil),
            WebSearchResult(title: "Duplicate Swift", url: "https://www.swift.org/concurrency#details", description: "", domain: "www.swift.org", rank: 4, modified: nil)
        ], nextOffset: nil)
    }
}
final class WebResearchTests: XCTestCase, @unchecked Sendable {
    func testBraveUsesFixedOriginHeaderAndPaginationWithoutLeakingCredentialToURL() async throws {
        let requests = SearchRequests()
        let provider = BraveSearchProvider(key: { "fixture-key" }, transport: { request in
            await requests.add(request)
            return Data(#"{"query":{"more_results_available":true},"web":{"results":[{"title":"Swift","url":"https://www.swift.org/documentation/","description":"Official <b>Swift</b> docs","age":"2 days ago","page_age":"2026-11-15"}]}}"#.utf8)
        })
        let result = try await provider.search(query: "Swift docs & tutorials", offset: 2, freshness: "pw")
        let captured = await requests.values
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].url?.host, "api.search.brave.com")
        XCTAssertEqual(captured[0].value(forHTTPHeaderField: "X-Subscription-Token"), "fixture-key")
        XCTAssertFalse(captured[0].url!.absoluteString.contains("fixture-key"))
        let parameters = URLComponents(url: captured[0].url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(parameters?.first(where: { $0.name == "offset" })?.value, "2")
        XCTAssertEqual(parameters?.first(where: { $0.name == "freshness" })?.value, "pw")
        XCTAssertEqual(result.results.first?.rank, 21)
        XCTAssertEqual(result.results.first?.domain, "www.swift.org")
        XCTAssertEqual(result.results.first?.pageDate, "2026-11-15")
        XCTAssertNil(result.results.first?.published)
        XCTAssertEqual(result.nextOffset, 3)
    }
    func testPageDeclaredMetadataKeepsDateKindsAndDoesNotTrustCrossOriginCanonical() {
        let html = #"<meta content="2026-11-01" property="article:published_time"><meta property='article:modified_time' content='2026-11-15'><link href="/canonical" rel="canonical">"#
        let metadata = WebText.metadata(html, base: URL(string: "https://www.swift.org/page")!)
        XCTAssertEqual(metadata["published"]?.string, "2026-11-01")
        XCTAssertEqual(metadata["modified"]?.string, "2026-11-15")
        XCTAssertEqual(metadata["canonical_url"]?.string, "https://www.swift.org/canonical")
        let bad = WebText.metadata(#"<link rel="canonical" href="https://evil.example/misleading">"#, base: URL(string: "https://www.swift.org/")!)
        XCTAssertNil(bad["canonical_url"])
    }
    func testBraveRejectsMalformedUnsafeAndOversizedResponses() throws {
        XCTAssertThrowsError(try BraveSearchProvider.parse(Data("{}".utf8), offset: 0, freshness: ""))
        XCTAssertThrowsError(try BraveSearchProvider.parse(Data(repeating: 0, count: 1_000_001), offset: 0, freshness: ""))
        let body = Data(#"{"query":{"more_results_available":false},"web":{"results":[{"title":"Bad","url":"javascript:bad()"},{"title":"Private","url":"https://127.0.0.1"},{"title":"Safe","url":"https://www.swift.org/"},{"title":"Duplicate","url":"https://www.swift.org/"}]}}"#.utf8)
        let result = try BraveSearchProvider.parse(body, offset: 9, freshness: "")
        XCTAssertEqual(result.results.count, 1)
        XCTAssertNil(result.nextOffset)
        for offset in [-1, 10] { XCTAssertThrowsError(try BraveSearchProvider.request(query: "Swift", offset: offset, freshness: "", key: "fixture")) }
        XCTAssertThrowsError(try BraveSearchProvider.request(query: "Swift", offset: 0, freshness: "hour", key: "fixture"))
        XCTAssertThrowsError(try BraveSearchProvider.request(query: "Swift", offset: 0, freshness: "", key: "fixture\r\nInjected: true"))
    }
    func testUnavailableAndMissingCredentialsNeverDispatchARequest() async throws {
        let requests = SearchRequests()
        for enabled in [false, true] {
            let provider = BraveSearchProvider(key: { nil }, enabled: { enabled }, transport: { request in
                await requests.add(request); return Data()
            })
            do { _ = try await provider.search(query: "Swift", offset: 0); XCTFail("Must fail without a connection") } catch {}
        }
        let count = await requests.values.count
        XCTAssertEqual(count, 0)
    }
    func testResearchUsesThreePublishersAndPreservesCitationsWithoutInventingDates() async throws {
        let requests = SearchRequests()
        let tool = ResearchTool(provider: ResearchSearchFixture(), fetch: { url in
            await requests.add(URLRequest(url: URL(string: url)!))
            return ToolResult("Excerpt", data: .object(["url": .string(url), "title": .string("Swift concurrency"), "text": .string(String(repeating: "Swift concurrency ", count: 1000))]))
        })
        let result = try await tool.execute(arguments: .object(["query": .string("Compare Swift concurrency")]))
        guard case .array(let sources) = result.data.object?["sources"], case .array(let searches) = result.data.object?["searches"] else { return XCTFail("Missing evidence") }
        XCTAssertEqual(sources.count, 3); XCTAssertEqual(searches.count, 1)
        XCTAssertEqual(result.data.object?["publisher_groups"], .number(3))
        XCTAssertEqual(result.data.object?["characters"], .number(24000))
        XCTAssertEqual(sources[0].object?["citation"]?.string, "S1")
        XCTAssertEqual(sources[0].object?["published"], .null)
        XCTAssertTrue(sources.allSatisfy { $0.object?["evidence_kind"]?.string == "page_excerpt" })
        let count = await requests.values.count
        XCTAssertEqual(count, 3)
    }
    func testExplicitSourcesAreDeduplicatedAndFailuresStayVisible() async throws {
        let tool = ResearchTool(provider: nil, fetch: { url in
            if url.contains("github") { throw URLError(.notConnectedToInternet) }
            return ToolResult("Excerpt", data: .object(["url": .string(url), "title": .string("Source"), "text": .string("Swift evidence")]))
        })
        let result = try await tool.execute(arguments: .object(["query": .string("Swift"), "urls": .array([.string("https://www.swift.org/"), .string("https://www.swift.org/#fragment"), .string("https://github.com/swiftlang/swift")])]))
        guard case .array(let sources) = result.data.object?["sources"], case .array(let failures) = result.data.object?["failures"] else { return XCTFail("Missing evidence") }
        XCTAssertEqual(result.state, .partiallyCompleted)
        XCTAssertEqual(sources.count, 1); XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.object?["url"]?.string, "https://github.com/swiftlang/swift")
    }
    func testFailedPageFetchIsExplicitlyASnippetNotAReadPage() async throws {
        let tool = ResearchTool(provider: ResearchSearchFixture(), fetch: { _ in throw ToolError.denied("Unsupported publisher") })
        let result = try await tool.execute(arguments: .object(["query": .string("Swift")]))
        guard case .array(let sources) = result.data.object?["sources"] else { return XCTFail("Missing evidence") }
        XCTAssertEqual(result.state, .partiallyCompleted)
        XCTAssertEqual(sources.count, 3)
        XCTAssertTrue(sources.allSatisfy { $0.object?["evidence_kind"]?.string == "search_snippet" })
        XCTAssertEqual(result.data.object?["page_fetches"], .number(0))
    }
    func testResearchCancellationDoesNotReturnSuccess() async throws {
        let tool = ResearchTool(provider: nil, fetch: { _ in throw CancellationError() })
        do {
            _ = try await tool.execute(arguments: .object(["query": .string("Swift"), "urls": .array([.string("https://www.swift.org/")])]))
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }
    func testDailyBudgetPersistsConservativeCountAndResetsAtUTCDateChange() async throws {
        let suite = "SottoWebBudgetTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "webSearchDailyLimit")
        // Create the defaults inside each actor to avoid passing shared mutable state.
        let first = SearchRequestBudget(defaults: UserDefaults(suiteName: suite)!, now: { Date(timeIntervalSince1970: 86_400) })
        try await first.reserve()
        do { try await first.reserve(); XCTFail("Daily cap must reject") } catch {}
        let restored = SearchRequestBudget(defaults: UserDefaults(suiteName: suite)!, now: { Date(timeIntervalSince1970: 86_400) })
        do { try await restored.reserve(); XCTFail("Cap must persist") } catch {}
        let tomorrow = SearchRequestBudget(defaults: UserDefaults(suiteName: suite)!, now: { Date(timeIntervalSince1970: 172_800) })
        try await tomorrow.reserve()
        XCTAssertEqual(defaults.integer(forKey: "webSearchUsageCount"), 1)
    }
}

final class LiveResearchContinuationTests: XCTestCase, @unchecked Sendable {
    func testActualThreePublisherEvidenceCollection() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_LIVE_WEB"] == "1" else { throw XCTSkip("Enable real public-source research") }
        let tool = ResearchTool()
        let result = try await tool.execute(arguments: .object(["query": .string("Swift programming language"), "urls": .array([
            .string("https://www.swift.org/documentation/"),
            .string("https://developer.apple.com/swift/"),
            .string("https://raw.githubusercontent.com/swiftlang/swift/main/README.md")
        ])]))
        guard case .array(let sources) = result.data.object?["sources"] else { return XCTFail("No source records") }
        XCTAssertEqual(sources.count, 3, result.encoded)
        XCTAssertEqual(result.data.object?["publisher_groups"], .number(3))
        XCTAssertTrue(sources.allSatisfy { $0.object?["evidence_kind"]?.string == "page_excerpt" })
    }
}
