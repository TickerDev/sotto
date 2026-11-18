import Foundation
import CoreGraphics
@preconcurrency import PDFKit
@preconcurrency import Vision
import SottoTools

/// Requested-document OCR only. Each page has a fixed raster budget and the
/// caller enforces document/page/text budgets before sending any result onward.
enum PDFPageOCR {
    static let maximumDimension = 2_000

    static func render(_ page: PDFPage) throws -> CGImage {
        try Task.checkCancellation()
        guard let source = page.pageRef else { throw ToolError.unavailable("A PDF page could not be rendered for local OCR.") }
        let box = source.getBoxRect(.mediaBox)
        guard box.origin.x.isFinite, box.origin.y.isFinite, box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else {
            throw ToolError.unavailable("A PDF page has invalid dimensions for local OCR.")
        }
        let rotated = abs(source.rotationAngle % 180) == 90
        let width = rotated ? box.height : box.width
        let height = rotated ? box.width : box.height
        // Ratios stay in 0...1 even for extreme but finite PDF dimensions.
        let largest = max(width, height)
        let pixelsWide = max(1, min(maximumDimension, Int(ceil(width / largest * CGFloat(maximumDimension)))))
        let pixelsHigh = max(1, min(maximumDimension, Int(ceil(height / largest * CGFloat(maximumDimension)))))
        guard let context = CGContext(data: nil, width: pixelsWide, height: pixelsHigh,
                                      bitsPerComponent: 8, bytesPerRow: pixelsWide * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ToolError.unavailable("Could not allocate the bounded PDF image for local OCR.")
        }
        let canvas = CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(canvas)
        context.concatenate(source.getDrawingTransform(.mediaBox, rect: canvas, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(source)
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw ToolError.unavailable("Could not render this PDF page for local OCR.") }
        return image
    }

    static func recognize(_ image: CGImage) async throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let cancellation = OCRCancellation(request)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
            catch { try Task.checkCancellation(); throw ToolError.unavailable("Local OCR could not read this PDF page.") }
            try Task.checkCancellation()
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        } onCancel: { cancellation.cancel() }
    }
}

/// Vision explicitly supports canceling an in-flight request. Configuration and
/// results stay on the OCR operation; only cancel() is called from another task.
private final class OCRCancellation: @unchecked Sendable {
    let request: VNRecognizeTextRequest
    init(_ request: VNRecognizeTextRequest) { self.request = request }
    func cancel() { request.cancel() }
}
