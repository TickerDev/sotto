import Foundation
import NaturalLanguage
@preconcurrency import PDFKit
import SottoTools

private struct IndexedDocument: Codable, Sendable {
    let path: String
    let modified: Date
    let bytes: Int
    let excerpt: String
    let vector: [Double]?
    let embeddingRevision: Int?
}
/// An automatic, bounded local document cache supplementing macOS Spotlight. No content leaves this actor through search results.
public actor LocalDocumentIndex {
    public static let shared = LocalDocumentIndex()
    private let file: URL
    private let selectedFolders: @Sendable () -> [String]
    private let excluded: @Sendable (URL) -> Bool
    private var generation = 0
    private var indexing = false
    private var scanEnumerator: FileManager.DirectoryEnumerator?
    private var scanRootIndex = 0
    private var scanSignature = ""
    private var completedScan = false
    private var records: [IndexedDocument]
    private let embedding: NLEmbedding?
    init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sotto/DocumentIndex/index.json"),
         folders: @escaping @Sendable () -> [String] = { LocalDocumentIndex.discoveryFolders() },
         excluded: @escaping @Sendable (URL) -> Bool = { DocumentSearchPrivacy.isExcluded($0) }) {
        self.file = file; self.selectedFolders = folders; self.excluded = excluded
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64_000_000,
           let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode([IndexedDocument].self, from: data), stored.count <= 2000 {
            records = stored
        } else { records = [] }
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }
    public nonisolated static var automaticEnabled: Bool {
        UserDefaults.standard.object(forKey: "automaticDocumentSearch") as? Bool ?? true
    }
    public nonisolated static func discoveryFolders() -> [String] {
        guard automaticEnabled else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.path, home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path,
                home.appendingPathComponent("Library/CloudStorage").path]
            + (UserDefaults.standard.stringArray(forKey: "documentIndexFolders") ?? [])
    }
    public func status() -> String {
        "\(records.count) documents ready for content matching. " + (indexing ? "Updating automatically." : "macOS file search is available immediately.")
    }
    private func roots() -> [URL] {
        Array(Set(selectedFolders())).sorted().prefix(16).compactMap { raw in
            guard let url = try? FilePolicy.url(raw), !excluded(url),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return url
        }
    }
    private func permitted(_ url: URL, roots: [URL]) -> Bool {
        guard !excluded(url) else { return false }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return roots.contains { path == $0.path || path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.deletingLastPathComponent().path)
        let data = try JSONEncoder().encode(records)
        guard data.count <= 64_000_000 else { throw ToolError.unavailable("Local index size limit reached") }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public func prune() throws {
        generation += 1
        scanEnumerator = nil; scanSignature = ""; scanRootIndex = 0; completedScan = false
        let approved = roots()
        let previous = records.count
        records.removeAll { !permitted(URL(fileURLWithPath: $0.path), roots: approved) }
        if records.count != previous { try persist() }
    }
    public func clear() throws {
        generation += 1
        scanEnumerator = nil; scanSignature = ""; scanRootIndex = 0; completedScan = false
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        records = []
    }
    public func rebuild(progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> ToolResult {
        guard !indexing else { throw ToolError.unavailable("Document indexing is already running") }
        indexing = true
        defer { indexing = false }
        let version = generation
        let approved = roots()
        guard !approved.isEmpty else { return ToolResult("Automatic document search is off or no document locations are accessible. macOS file search can still be used.", state: .clarificationRequired) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(40))
        var updated = Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0) })
        var newCount = 0
        var seen = Set<String>(); var inspected = 0; var skipped = 0; var bounded = false
        let signature = approved.map(\.path).joined(separator: "\n")
        if signature != scanSignature || completedScan {
            scanEnumerator = nil; scanRootIndex = 0; scanSignature = signature; completedScan = false
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]
        while scanRootIndex < approved.count {
            try Task.checkCancellation()
            guard generation == version else { throw ToolError.unavailable("Document search settings changed; discovery will resume automatically.") }
            if inspected >= 5000 || newCount >= 200 || ContinuousClock.now >= deadline { bounded = true; break }
            if scanEnumerator == nil {
                scanEnumerator = FileManager.default.enumerator(at: approved[scanRootIndex], includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
            }
            guard let enumerator = scanEnumerator, let url = enumerator.nextObject() as? URL else {
                scanEnumerator = nil; scanRootIndex += 1; continue
            }
                try Task.checkCancellation()
                inspected += 1
                guard permitted(url, roots: approved), let values = try? url.resourceValues(forKeys: keys),
                      values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
                if values.isDirectory == true {
                    if values.isPackage == true || enumerator.level >= 12 || ["Library", "node_modules", ".build", "DerivedData", "Pods", "Caches"].contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    continue
                }
                let kind = url.pathExtension.lowercased()
                guard DocumentTextFormats.supports(url.path), values.isRegularFile == true else { continue }
                guard let size = values.fileSize, size <= 2_000_000, let modified = values.contentModificationDate,
                      seen.insert(url.path).inserted, FileManager.default.isReadableFile(atPath: url.path) else { skipped += 1; continue }
                if let cached = updated[url.path], cached.modified == modified, cached.bytes == size { continue }
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: 2_000_001) ?? Data()
                    guard data.count <= 2_000_000 else { skipped += 1; continue }
                    let text: String
                    if kind == "pdf" {
                        guard let pdf = PDFDocument(data: data), !pdf.isLocked else { skipped += 1; continue }
                        var excerpt = ""
                        for index in 0..<min(10, pdf.pageCount) {
                            try Task.checkCancellation()
                            excerpt += String((pdf.page(at: index)?.string ?? "").prefix(max(0, 8000 - excerpt.count)))
                            if excerpt.count >= 8000 { break }
                        }
                        text = excerpt
                    } else { text = try NativeDocumentText.extract(data, kind: kind, limit: 8000).text }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { skipped += 1; continue }
                    // Match an excerpt, not the full document. Missing models use lexical ranking.
                    let vector = embedding?.vector(for: String((url.lastPathComponent + ". " + text).prefix(1000)))
                    updated[url.path] = IndexedDocument(path: url.path, modified: modified, bytes: size, excerpt: text, vector: vector, embeddingRevision: embedding?.revision)
                    newCount += 1
                    if newCount % 10 == 0 { await progress("Updated \(newCount) documents locally"); await Task.yield() }
                } catch is CancellationError { throw CancellationError() }
                catch { skipped += 1 }
        }
        completedScan = scanRootIndex >= approved.count
        try Task.checkCancellation()
        guard generation == version else { throw ToolError.unavailable("Document search settings changed. Automatic discovery will resume with the current settings.") }
        let previous = records
        let currentRoots = roots()
        records = Array(updated.values.filter { permitted(URL(fileURLWithPath: $0.path), roots: currentRoots) && FileManager.default.fileExists(atPath: $0.path) }.sorted { $0.modified > $1.modified }.prefix(2000))
        do { try persist() } catch { records = previous; throw error }
        return ToolResult("Indexed \(records.count) document excerpts locally; skipped \(skipped). \(bounded ? "More documents will be processed automatically in the next background batch." : "") PDF scans are not OCRed during indexing. No document text was sent online.", data: .object(["indexed": .number(Double(records.count)), "skipped": .number(Double(skipped)), "bounded": .bool(bounded), "semantic_available": .bool(embedding != nil)]), state: bounded || skipped > 0 ? .partiallyCompleted : .success)
    }
    func search(query: String, fileExtension: String = "", modifiedSince: Date? = nil) throws -> ToolResult {
        try Task.checkCancellation()
        guard !query.isEmpty, query.count <= 500 else { throw ToolError.invalid("Provide a short document search phrase") }
        let approved = roots()
        guard !approved.isEmpty else { return ToolResult("Automatic document search is disabled or document access is unavailable. Use macOS file search.", state: .unsupported) }
        let queryVector = embedding?.vector(for: query)
        let tokens = Set(query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        let candidates: [(IndexedDocument, Double)] = records.compactMap { record in
            let url = URL(fileURLWithPath: record.path)
            guard permitted(url, roots: approved),
                  fileExtension.isEmpty || url.pathExtension.lowercased() == fileExtension.lowercased(),
                  modifiedSince == nil || record.modified >= modifiedSince!,
                  FileManager.default.isReadableFile(atPath: record.path),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  values.contentModificationDate == record.modified, values.fileSize == record.bytes else { return nil }
            let text = (url.lastPathComponent + " " + record.excerpt).lowercased()
            let lexical = tokens.isEmpty ? 0 : Double(tokens.filter { text.contains($0) }.count) / Double(tokens.count)
            let semantic: Double
            if record.embeddingRevision == embedding?.revision, let vector = record.vector, let queryVector {
                semantic = Self.cosine(vector, queryVector)
            } else { semantic = 0 }
            guard lexical > 0 || semantic > 0.25 else { return nil }
            return (record, lexical * 0.65 + max(0, semantic) * 0.35)
        }.sorted { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }
        let files = candidates.prefix(20).map { FileSearchMatch(path: $0.0.path, modified: $0.0.modified) }
        return ToolResult("Found \(files.count) indexed document matches using \(queryVector == nil ? "local phrase matching" : "local phrase and English semantic matching"). Only stored excerpts were searched; stale files are omitted. Choose a match before reading it.", data: FileSearchResults(files: files).data)
    }
    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let norm = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 })
        return norm.isFinite && norm > 0 && dot.isFinite ? dot / norm : 0
    }
}
struct FileIndexTool: Tool {
    let descriptor = ToolDescriptor(id: "files.index", description: "Rebuild or clear Sotto’s automatic local document cache after approval. Accessible user-document locations are discovered automatically; exclusions are respected. Bounded PDF/TXT/Markdown/RTF/DOCX excerpts and optional local English embeddings stay on this Mac. No OCR during indexing.", properties: ["action": textProperty("Action", choices: ["refresh", "clear"])], required: ["action"], risk: .consequential, capabilities: [.files], timeoutSeconds: 50)
    func execute(arguments: JSONValue) async throws -> ToolResult { try await execute(arguments: arguments, progress: { _ in }) }
    func execute(arguments: JSONValue, progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult {
        try descriptor.validate(arguments)
        try Task.checkCancellation()
        if arguments.object?["action"]?.string == "clear" {
            try await LocalDocumentIndex.shared.clear()
            return ToolResult("Cleared Sotto’s local document index. Your documents were not changed.")
        }
        return try await LocalDocumentIndex.shared.rebuild(progress: progress)
    }
}
