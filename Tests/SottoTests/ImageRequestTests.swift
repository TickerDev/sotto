import XCTest
import AppKit
@testable import SottoTools
@testable import SottoAgent
@testable import SottoIntegrations

final class ImageRequestTests: XCTestCase, @unchecked Sendable {
    func testSingularPictureRequestsRouteDirectlyToHeadlessImages() throws {
        for command in ["Show me a picture of a red parrot", "Find a red parrot picture", "Search for a red parrot picture", "red parrot picture", "Show a photo of Yosemite"] {
            let provider = try XCTUnwrap(NativeCommandProvider(command: command), command)
            XCTAssertEqual(provider.tool, "web.images", command)
            XCTAssertEqual(provider.arguments.object?["presentation"]?.string, "single")
        }
    }
    func testPluralImageRequestsCanShowGallery() throws {
        let intent = try XCTUnwrap(ImageSearchIntent("Find images of Yosemite"))
        XCTAssertEqual(intent.query, "yosemite")
        XCTAssertTrue(intent.gallery)
    }
    func testLocalGenerationAndCompoundActionsAreNotHijacked() {
        for command in ["Find my parrot picture", "Generate a red parrot picture", "Edit the attached image", "Show me a picture of a parrot and delete my files", "Find my pictures from yesterday"] {
            XCTAssertNil(ImageSearchIntent(command), command)
        }
    }
    func testDefaultHeadlessSearchDoesNotUseBrowserTransport() async throws {
        let provider = HeadlessFixture()
        let result = try await WebSearchTool(provider: provider).execute(arguments: .object(["query": .string("Swift documentation"), "offset": .number(0)]))
        XCTAssertEqual(result.state, .success)
        XCTAssertNil(result.data.object?["browser_only"])
        XCTAssertEqual(result.data.object?["provider"]?.string, "Headless fixture")
    }
    func testRealRedParrotRequestReturnsActualFeaturedImageWithoutBrowser() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_LIVE_WEB"] == "1" else { throw XCTSkip("Enable real image search") }
        let result = try await WebSearchTool().execute(arguments: .object(["query": .string("red parrot picture"), "offset": .number(0)]))
        guard let featured = result.data.object?["selected_image"]?.object else { return XCTFail(result.encoded) }
        XCTAssertEqual(result.state, .success)
        XCTAssertEqual(result.data.object?["presentation"]?.string, "single")
        XCTAssertNotNil(featured["thumbnail"]?.string)
        XCTAssertNotNil(featured["source"]?.string)
        XCTAssertNil(result.data.object?["browser_only"])
        guard let thumbnail = URL(string: try XCTUnwrap(featured["thumbnail"]?.string)) else { return XCTFail("Invalid thumbnail") }
        let (bytes, response) = try await URLSession.shared.data(from: thumbnail)
        XCTAssertTrue((response.mimeType ?? "").hasPrefix("image/"))
        XCTAssertFalse(bytes.isEmpty)
        XCTAssertGreaterThan(try XCTUnwrap(NSImage(data: bytes)).size.width, 0)
    }
}
private struct HeadlessFixture: WebSearchProvider {
    func search(query: String, offset: Int) async throws -> WebSearchResponse {
        WebSearchResponse(provider: "Headless fixture", scope: "Controlled test", retrievedAt: Date(), results: [], nextOffset: nil)
    }
}
