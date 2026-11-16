import XCTest
import SottoTools
import SottoAgent
import SottoSecurity
@testable import SottoIntegrations
@testable import SottoUI

private actor FileActionProbe {
    var actions: [JSONValue] = []
    func record(_ arguments: JSONValue) { actions.append(arguments) }
}
private struct SearchFixture: Tool {
    let descriptor = SearchFilesTool().descriptor
    let files: [FileSearchMatch]
    func execute(arguments: JSONValue) async throws -> ToolResult {
        ToolResult("Found matching files", data: FileSearchResults(files: files).data)
    }
}
private struct OpenFixture: Tool {
    let descriptor = FileTool().descriptor
    let probe: FileActionProbe
    func execute(arguments: JSONValue) async throws -> ToolResult { await probe.record(arguments); return ToolResult("Opened selected file") }
}

final class FileSearchTests: XCTestCase, @unchecked Sendable {
    func testResumeRankingIncludesAccentsAndCVAndRejectsTechnicalNoise() {
        let paths = ["/Users/example/Library/resume.pdf", "/Users/example/Code/resume.swift", "/Users/example/Documents/Résumé.pdf", "/Users/example/Downloads/Dor_CV.docx", "/Users/example/Documents/resumeData.txt"]
        let matches = FileSearchRanking.ranked(paths.map { FileSearchMatch(path: $0) }, query: "resume")
        XCTAssertEqual(matches.map(\.name), ["Résumé.pdf", "Dor_CV.docx"])
        XCTAssertEqual(FileSearchRanking.terms("résumé"), ["resume", "cv", "curriculum vitae"])
    }
    func testSearchDataRoundTripsAndDuplicatesAreRemoved() throws {
        let match = FileSearchMatch(path: "/tmp/resume.pdf", modified: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(FileSearchResults.decode(FileSearchResults(files: [match]).data)?.files, [match])
        XCTAssertEqual(FileSearchRanking.ranked([match, match], query: "resume"), [match])
    }
    func testICloudAndNumberedResumeNamesAreNotHiddenWithLibraryNoise() {
        let paths = ["/Users/example/Library/Mobile Documents/com~apple~CloudDocs/Downloads/resume (1).pdf", "/Users/example/Library/CloudStorage/Drive/Resume2026.pdf", "/Users/example/Library/Caches/resume.txt"]
        let results = FileSearchRanking.ranked(paths.map { FileSearchMatch(path: $0) }, query: "resume")
        XCTAssertEqual(Set(results.map(\.path)), Set(paths.prefix(2)))
    }
    func testLatestPDFUsesModificationDateBeforeFolderPreference() {
        let older = FileSearchMatch(path: "/Users/example/Documents/older.pdf", modified: Date(timeIntervalSince1970: 1))
        let newer = FileSearchMatch(path: "/Users/example/Code/newer.pdf", modified: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(FileSearchRanking.ranked([older, newer], query: ".pdf"), [newer, older])
    }
    func testFindRequestSearchesWithoutAssumingPDFOrRequiringIntelligence() throws {
        for command in ["Find my resume", "Find my résumé", "Can you find my CV?", "Please find my latest resume"] {
            let provider = try XCTUnwrap(NativeCommandProvider(command: command))
            XCTAssertEqual(provider.tool, "find_files")
            XCTAssertFalse(provider.arguments.object?["name"]?.string?.contains("pdf") == true)
        }
        XCTAssertNil(NativeCommandProvider(command: "Find my resume and send it to my boss"))
    }
    @MainActor func testNativeMatchesBecomeActionsAndSelectedFileOpensExactlyOnce() async throws {
        let match = FileSearchMatch(path: "/tmp/example-resume.pdf"), probe = FileActionProbe()
        let app = AppModel(preferences: Preferences(), startServices: false, registry: ToolRegistry([SearchFixture(files: [match]), OpenFixture(probe: probe)]))
        defer { app.shutdown() }
        app.submit("Find my resume")
        for _ in 0..<100 where app.state != .completed { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(app.fileMatches, [match])
        XCTAssertEqual(app.state, .completed)
        let before = await probe.actions
        XCTAssertTrue(before.isEmpty)
        app.openFileMatch(FileSearchMatch(path: "/tmp/not-a-search-result.pdf"))
        XCTAssertEqual(app.fileMatches, [match], "An invented path cannot be opened through the result action")
        app.openFileMatch(match)
        for _ in 0..<100 {
            if await probe.actions.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let actions = await probe.actions
        XCTAssertEqual(actions, [.object(["path": .string(match.path), "action": .string("open")])])
    }
    func testActualSpotlightResumeSearch() async throws {
        guard ProcessInfo.processInfo.environment["SOTTO_FILE_SEARCH_TEST"] == "1" else { throw XCTSkip("Opt-in local Spotlight search; no model or file opening") }
        let result = try await SearchFilesTool().execute(arguments: .object(["name": .string("resume")]))
        let files = try XCTUnwrap(FileSearchResults.decode(result.data)).files
        print("Live Spotlight résumé document matches: \(files.count)")
        XCTAssertLessThanOrEqual(files.count, 20)
        XCTAssertEqual(FileSearchRanking.ranked(files, query: "resume"), files)
    }
    func testDocumentFallbackFindsNestedResumeAndSkipsCodeDependencies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for relative in ["Job applications/Résumé.pdf", "node_modules/fixture/resume.pdf", "Letters/Dor_CV.docx"] {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let files = try await DocumentFolderSearch(roots: [root]).search("resume")
        XCTAssertEqual(Set(files.map(\.name)), Set(["Résumé.pdf", "Dor_CV.docx"]))
    }
    func testCancelledFallbackDoesNotReturnStaleResults() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DocumentFolderSearch(roots: []).search("resume")
        }
        do { _ = try await task.value; XCTFail("Cancelled search returned results") } catch is CancellationError {}
    }
}
