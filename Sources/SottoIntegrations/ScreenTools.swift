import AppKit
import ScreenCaptureKit
import Vision
import SottoTools

struct ScreenTool: Tool {
    let action: String
    var descriptor: ToolDescriptor { ToolDescriptor(id: "screen." + action, description: action == "capture" ? "Capture the main display after explicit approval and Screen Recording authorization. Saves a local PNG; does not upload the image." : "Capture the main display and read visible text with local Vision OCR after explicit approval. Extracted text is shared with the active reasoning provider. OCR may be inaccurate.", properties: [:], required: [], risk: .consequential, capabilities: [.screen], timeoutSeconds: 25, permissions: ["Screen Recording", "Explicit capture approval"]) }
    @MainActor func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            return ToolResult("Allow Screen Recording for Sotto in System Settings, then try again. macOS may require restarting Sotto.", state: .permissionRequired)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { throw ToolError.unavailable("The main display cannot be captured") }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = min(display.width, 3840); config.height = Int(Double(display.height) * Double(config.width) / Double(max(1, display.width)))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        if action == "readText" {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            return ToolResult("Read visible text with local OCR. Recognition may contain errors.", data: .object(["text": .string(String(text.prefix(16_000))), "truncated": .bool(text.count > 16_000), "ocr": .bool(true), "untrusted": .bool(true)]))
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw ToolError.unavailable("Screenshot encoding failed") }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Sotto/Captures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: file, options: .atomic)
        guard FileManager.default.fileExists(atPath: file.path) else { throw ToolError.unavailable("Screenshot save could not be verified") }
        return ToolResult("Saved a local screenshot. It has not been uploaded.", data: .object(["path": .string(file.path), "width": .number(Double(image.width)), "height": .number(Double(image.height))]))
    }
}
