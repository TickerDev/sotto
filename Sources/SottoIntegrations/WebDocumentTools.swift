import Foundation
import PDFKit
import SottoTools

struct WebDocumentTool: Tool {
    let action: String
    var descriptor: ToolDescriptor { ToolDescriptor(id: "web." + action, description: action == "download" ? "Download an explicitly requested PDF, image or text file from a supported public publisher to Downloads, after approval. Streams transfer progress, limits files to 20 MB and never executes content." : "Read a public PDF from a supported publisher using PDFKit, after approval to share extracted content with the active reasoning provider. Maximum 20 MB, 50 pages and 16000 characters. Uses bounded local OCR only for textless pages (up to 5); reports OCR, skipped pages and excerpts.", properties: ["url": textProperty("HTTPS document URL from a supported publisher")], required: ["url"], risk: .consequential, capabilities: [.web, .files], timeoutSeconds: 40) }
    func execute(arguments: JSONValue) async throws -> ToolResult { try await execute(arguments: arguments, progress: { _ in }) }
    func execute(arguments: JSONValue, progress: @escaping @Sendable (String) async -> Void) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let url = try PublicWebPolicy.url(arguments.object?["url"]?.string ?? "", retrieval: true)
        let pdf = url.pathExtension.lowercased() == "pdf"
        if action == "readPDF" && !pdf { throw ToolError.invalid("Choose a direct PDF URL") }
        let extensions = ["pdf", "png", "jpg", "jpeg", "gif", "txt", "md"]
        guard extensions.contains(url.pathExtension.lowercased()) else { throw ToolError.denied("Only PDF, PNG, JPEG, GIF and plain text downloads are supported") }
        let mime: [String]
        switch url.pathExtension.lowercased() {
        case "pdf": mime = ["application/pdf", "application/octet-stream"]
        case "png": mime = ["image/png"]
        case "jpg", "jpeg": mime = ["image/jpeg"]
        case "gif": mime = ["image/gif"]
        default: mime = ["text/plain", "text/markdown"]
        }
        let (data, finalURL) = try await PublicWebClient().get(url, allowedMIME: mime, limit: 20_000_000, allowAttachments: true, progress: progress)
        try Task.checkCancellation()
        if pdf {
            guard data.starts(with: Data("%PDF-".utf8)), let document = PDFDocument(data: data), !document.isLocked else { throw ToolError.invalid("The response is not a readable, unlocked PDF") }
            if action == "readPDF" {
                return try await OnlinePDFReader.read(data: data, source: finalURL)
            }
        } else if mime.contains("image/png") {
            guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw ToolError.invalid("Invalid PNG response") }
        } else if mime.contains("image/jpeg") {
            guard data.starts(with: [255, 216, 255]) else { throw ToolError.invalid("Invalid JPEG response") }
        } else if mime.contains("image/gif") {
            guard data.starts(with: Data("GIF8".utf8)) else { throw ToolError.invalid("Invalid GIF response") }
        } else {
            guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw ToolError.invalid("Response is not supported plain text") }
        }
        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        // A unique directory prevents overwrite races and untrusted filenames.
        let directory = downloads.appendingPathComponent("Sotto-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let target = directory.appendingPathComponent("download." + url.pathExtension.lowercased())
        do {
            try data.write(to: target, options: [.withoutOverwriting])
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            guard (attributes[.size] as? NSNumber)?.intValue == data.count else { throw ToolError.unavailable("Downloaded file size could not be verified") }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return ToolResult("Saved \(data.count) bytes to \(target.path). The file was not opened.", data: .object(["path": .string(target.path), "source": .string(finalURL.absoluteString), "bytes": .number(Double(data.count))]))
    }
}
