import XCTest
@testable import SottoIntegrations
@testable import SottoTools
@testable import SottoUI

private final class IndexScopes: @unchecked Sendable {
    private let lock = NSLock()
    private var roots: [String]
    init(_ roots: [String]) { self.roots = roots }
    func get() -> [String] { lock.withLock { roots } }
    func set(_ roots: [String]) { lock.withLock { self.roots = roots } }
}
final class LocalDocumentIndexTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let documents = root.appendingPathComponent("documents")
        let index = root.appendingPathComponent("index/index.json")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, documents, index)
    }
    private func assertSameFile(_ path: String?, _ expected: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(path, file: file, line: line)
        let a = try FileManager.default.attributesOfItem(atPath: actual)
        let b = try FileManager.default.attributesOfItem(atPath: expected.path)
        XCTAssertEqual(a[.systemFileNumber] as? NSNumber, b[.systemFileNumber] as? NSNumber, file: file, line: line)
        XCTAssertEqual(a[.systemNumber] as? NSNumber, b[.systemNumber] as? NSNumber, file: file, line: line)
    }
    func testRealContentIndexFindsUnrelatedFilenameAndPersistsWithoutUploadingText() async throws {
        let (_, documents, file) = try fixture()
        let essay = documents.appendingPathComponent("assignment-04.txt")
        try Data("My engineering ethics assignment discusses professional responsibility and safety.".utf8).write(to: essay)
        try Data("Shopping list: bread, milk and tomatoes.".utf8).write(to: documents.appendingPathComponent("groceries.md"))
        let scope = IndexScopes([documents.path])
        let index = LocalDocumentIndex(file: file, folders: { scope.get() }, excluded: { _ in false })
        let result = try await index.rebuild()
        XCTAssertEqual(result.data.object?["indexed"], .number(2))
        let match = try await index.search(query: "engineering ethics")
        let paths = try XCTUnwrap(FileSearchResults.decode(match.data)).files
        try assertSameFile(paths.first?.path, essay)
        XCTAssertNil(match.data.object?["text"], "Index excerpts must not be returned to the reasoning provider")
        let restored = LocalDocumentIndex(file: file, folders: { scope.get() }, excluded: { _ in false })
        let restoredResult = try await restored.search(query: "engineering ethics")
        try assertSameFile(FileSearchResults.decode(restoredResult.data)?.files.first?.path, essay)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
    func testIndexSkipsExcludedFoldersSymlinksUnsupportedFilesAndStaleDocuments() async throws {
        let (root, documents, file) = try fixture()
        let excluded = documents.appendingPathComponent("excluded")
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try Data("Engineering ethics secrets".utf8).write(to: excluded.appendingPathComponent("private.txt"))
        let target = root.appendingPathComponent("outside.txt")
        try Data("Engineering ethics outside approved scope".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: documents.appendingPathComponent("link.txt"), withDestinationURL: target)
        try Data("Engineering ethics executable".utf8).write(to: documents.appendingPathComponent("script.sh"))
        let publicFile = documents.appendingPathComponent("notes.txt")
        try Data("Engineering ethics public assignment".utf8).write(to: publicFile)
        let index = LocalDocumentIndex(file: file, folders: { [documents.path] }, excluded: { $0.lastPathComponent == "excluded" || $0.deletingLastPathComponent().lastPathComponent == "excluded" })
        let result = try await index.rebuild()
        XCTAssertEqual(result.data.object?["indexed"], .number(1))
        let before = try await index.search(query: "engineering ethics")
        XCTAssertEqual(FileSearchResults.decode(before.data)?.files.count, 1)
        try Data("Changed contents after indexing with a different length".utf8).write(to: publicFile)
        let after = try await index.search(query: "engineering ethics")
        XCTAssertEqual(FileSearchResults.decode(after.data)?.files.count, 0)
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(contents.contains("secrets")); XCTAssertFalse(contents.contains("outside approved scope"))
    }
    func testRemovingApprovedScopePurgesPersistedExcerpts() async throws {
        let (_, documents, file) = try fixture()
        try Data("Private local essay engineering ethics".utf8).write(to: documents.appendingPathComponent("essay.txt"))
        let scopes = IndexScopes([documents.path])
        let index = LocalDocumentIndex(file: file, folders: { scopes.get() }, excluded: { _ in false })
        _ = try await index.rebuild()
        scopes.set([])
        try await index.prune()
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("Private local essay"))
        let result = try await index.search(query: "essay")
        XCTAssertEqual(result.state, .unsupported)
        try await index.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testScopeRevocationDuringIndexingCannotCommitOldContent() async throws {
        let (_, documents, file) = try fixture()
        for i in 0..<12 { try Data("Engineering ethics assignment \(i)".utf8).write(to: documents.appendingPathComponent("\(i).txt")) }
        let scopes = IndexScopes([documents.path])
        let index = LocalDocumentIndex(file: file, folders: { scopes.get() }, excluded: { _ in false })
        do {
            _ = try await index.rebuild(progress: { _ in scopes.set([]); try? await index.prune() })
            XCTFail("Scope change must invalidate the build")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testAutomaticDiscoveryNeedsNoSelectedFolderConfiguration() {
        if LocalDocumentIndex.automaticEnabled {
            XCTAssertTrue(LocalDocumentIndex.discoveryFolders().contains(FileManager.default.homeDirectoryForCurrentUser.path))
        }
    }
    func testIncrementalBatchesContinueBeyondTheFirstTwoHundredDocuments() async throws {
        let (_, documents, file) = try fixture()
        for i in 0..<205 {
            try Data("Local engineering ethics record \(i)".utf8).write(to: documents.appendingPathComponent("\(i).txt"))
        }
        let index = LocalDocumentIndex(file: file, folders: { [documents.path] }, excluded: { _ in false })
        let first = try await index.rebuild()
        XCTAssertEqual(first.data.object?["indexed"], .number(200))
        XCTAssertEqual(first.data.object?["bounded"], .bool(true))
        let second = try await index.rebuild()
        XCTAssertEqual(second.data.object?["indexed"], .number(205))
        XCTAssertEqual(second.data.object?["bounded"], .bool(false))
        let unchanged = try await index.rebuild()
        XCTAssertEqual(unchanged.data.object?["indexed"], .number(205))
    }
    func testExactWebResultFollowupUsesOnlyActualCurrentURLs() throws {
        let results = [WebSearchResult(title: "Swift", url: "https://www.swift.org/", description: "", domain: "www.swift.org", rank: 1, modified: nil)]
        let action = try XCTUnwrap(WebResultFollowup.action("Open the first search result.", results: results))
        XCTAssertEqual(action.tool, "web.open")
        XCTAssertEqual(action.arguments.object?["url"]?.string, results[0].url)
        XCTAssertNil(WebResultFollowup.action("Open the second search result", results: results))
        XCTAssertNil(WebResultFollowup.action("Open the first search result and buy a book", results: results))
    }
    func testRealEnglishSemanticRankingWhenModelIsAvailable() async throws {
        let (_, documents, file) = try fixture()
        let essay = documents.appendingPathComponent("essay.txt")
        try Data("Engineering ethics concerns professional duties, public safety, and responsible decisions in technological design.".utf8).write(to: essay)
        try Data("Chocolate cake ingredients include flour, eggs, sugar, cocoa, and butter.".utf8).write(to: documents.appendingPathComponent("recipe.txt"))
        let index = LocalDocumentIndex(file: file, folders: { [documents.path] }, excluded: { _ in false })
        let built = try await index.rebuild()
        guard built.data.object?["semantic_available"] == .bool(true) else { throw XCTSkip("Local English sentence embedding model is unavailable") }
        let result = try await index.search(query: "Moral obligations of engineers")
        try assertSameFile(FileSearchResults.decode(result.data)?.files.first?.path, essay)
    }
}
