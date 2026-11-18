import Foundation
import SottoTools

/// Reuses the production local-document reader and its OCR/cancellation budgets.
/// Temporary PDFs are owner-only and removed before any result is returned.
enum OnlinePDFReader {
    static func read(data: Data, source: URL) async throws -> ToolResult {
        try Task.checkCancellation()
        guard data.count <= 20_000_000, data.starts(with: Data("%PDF-".utf8)) else { throw ToolError.invalid("The response is not a supported PDF") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Sotto-PDF-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("online-document.pdf")
        try data.write(to: file, options: .withoutOverwriting)
        let result = try await DocumentTextReader().read(path: file.path)
        try Task.checkCancellation()
        var output = result.data.object ?? [:]
        output["url"] = .string(source.absoluteString)
        output["page_count"] = output["total_pages"] ?? .number(0)
        output["untrusted"] = .bool(true)
        output["retrieved_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        output["partial"] = output["truncated"] ?? .bool(false)
        let partial = output["truncated"] == .bool(true)
        return ToolResult(result.summary.replacingOccurrences(of: "online-document.pdf", with: "online PDF"), data: .object(output), state: partial ? .partiallyCompleted : .success)
    }
}
