import XCTest
import CoreGraphics
import CoreText
@preconcurrency import PDFKit
import SottoTools
@testable import SottoIntegrations

private actor OCRPageProbe {
    var calls = 0
    func text() -> String { calls += 1; return "Scan \(calls)" }
}
final class PDFOCRTests: XCTestCase, @unchecked Sendable {
    private func scan(_ text: String?) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1224, height: 1584, bitsPerComponent: 8, bytesPerRow: 1224 * 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1224, height: 1584))
        if let text { draw(text, size: 32, context: context, at: CGPoint(x: 80, y: 1400)) }
        return try XCTUnwrap(context.makeImage())
    }
    private func draw(_ text: String, size: CGFloat, context: CGContext, at point: CGPoint) {
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil)]
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
    private func pdf(_ pages: [(text: String?, scanned: Bool)]) throws -> Data {
        let output = NSMutableData()
        let target = try XCTUnwrap(CGDataConsumer(data: output))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: target, mediaBox: &box, nil))
        for page in pages {
            context.beginPDFPage(nil)
            if page.scanned { context.draw(try scan(page.text), in: box) }
            else if let text = page.text { draw(text, size: 16, context: context, at: CGPoint(x: 40, y: 700)) }
            context.endPDFPage()
        }
        context.closePDF(); return output as Data
    }
    private func fixture(_ bytes: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Scan.pdf"); try bytes.write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return file
    }

    func testRealVisionReadsImageOnlyPDFAndDisclosesOCR() async throws {
        let bytes = try pdf([("Sotto deadline Friday. Budget 200 dollars.", true)])
        let document = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertTrue((document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Fixture must have no embedded text")
        let file = try fixture(bytes)
        let result = try await ReadDocumentTool().execute(arguments: .object(["path": .string(file.path)]))
        let text = try XCTUnwrap(result.data.object?["text"]?.string).lowercased()
        XCTAssertTrue(text.contains("deadline friday"), text)
        XCTAssertTrue(text.contains("200 dollars"), text)
        XCTAssertEqual(result.data.object?["ocr_pages_with_text"], .array([.number(1)]))
        XCTAssertEqual(result.data.object?["truncated"], .bool(false))
        XCTAssertTrue(result.summary.contains("local OCR"))
        XCTAssertFalse(result.summary.contains("200 dollars"), "History summary must not retain recognized document content")
    }
    func testOnlinePDFReusesRealVisionAndReportsExactSource() async throws {
        let bytes = try pdf([("Online research budget 200 dollars.", true)])
        let source = URL(string: "https://www.swift.org/research.pdf")!
        let result = try await OnlinePDFReader.read(data: bytes, source: source)
        XCTAssertTrue(result.data.object?["text"]?.string?.lowercased().contains("200 dollars") == true)
        XCTAssertEqual(result.data.object?["url"]?.string, source.absoluteString)
        XCTAssertEqual(result.data.object?["ocr_pages_with_text"], .array([.number(1)]))
        XCTAssertTrue(result.summary.contains("local OCR"))
        XCTAssertEqual(result.state, .success)
        XCTAssertNil(result.data.object?["path"])
    }
    func testEmbeddedTextSkipsOCR() async throws {
        let file = try fixture(pdf([("Original embedded text", false)]))
        let reader = DocumentTextReader { _ in XCTFail("Embedded text must not trigger OCR"); return "Wrong" }
        let result = try await reader.read(path: file.path)
        XCTAssertTrue(result.data.object?["text"]?.string?.contains("Original embedded text") == true)
        XCTAssertEqual(result.data.object?["ocr_pages_attempted"], .array([]))
    }
    func testOCRBudgetStillReadsLaterEmbeddedPagesAndMarksSkippedScansPartial() async throws {
        let pages = Array(repeating: (text: String?.none, scanned: true), count: 6) + [(text: "Later embedded page", scanned: false)]
        let file = try fixture(pdf(pages)), probe = OCRPageProbe()
        let result = try await DocumentTextReader { _ in await probe.text() }.read(path: file.path)
        let calls = await probe.calls
        XCTAssertEqual(calls, DocumentTextReader.ocrPageLimit)
        XCTAssertEqual(result.data.object?["ocr_skipped_pages"], .array([.number(6)]))
        XCTAssertEqual(result.data.object?["pages_inspected"], .number(7))
        XCTAssertEqual(result.data.object?["truncated"], .bool(true))
        let text = try XCTUnwrap(result.data.object?["text"]?.string)
        XCTAssertTrue(text.hasPrefix("Scan 1\n\nScan 2"))
        XCTAssertTrue(text.hasSuffix("Later embedded page"))
    }
    func testFailedOCRPreservesOtherTextAsAnExplicitPartialRead() async throws {
        let file = try fixture(pdf([(nil, true), ("Readable second page", false)]))
        let result = try await DocumentTextReader { _ in throw ToolError.unavailable("Fixture failure") }.read(path: file.path)
        XCTAssertEqual(result.data.object?["unreadable_pages"], .array([.number(1)]))
        XCTAssertEqual(result.data.object?["truncated"], .bool(true))
        XCTAssertTrue(result.data.object?["text"]?.string?.contains("Readable second page") == true)
    }
    func testCanceledOCRCannotReturnPartialContent() async throws {
        let file = try fixture(pdf([("Earlier text", false), (nil, true)]))
        let reader = DocumentTextReader { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return "Must not escape cancellation"
        }
        let task = Task { try await reader.read(path: file.path) }
        do { _ = try await task.value; XCTFail("Canceled OCR returned document content") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testOCRTextStillUsesSharedCharacterLimit() async throws {
        let file = try fixture(pdf([(nil, true)]))
        let result = try await DocumentTextReader { _ in String(repeating: "é", count: 17_000) }.read(path: file.path)
        XCTAssertEqual(result.data.object?["text"]?.string?.count, DocumentTextReader.textLimit)
        XCTAssertEqual(result.data.object?["truncated"], .bool(true))
    }
    func testRasterIsBoundedAndHonorsPDFRotation() throws {
        let document = try XCTUnwrap(PDFDocument(data: pdf([(nil, true)])))
        let page = try XCTUnwrap(document.page(at: 0))
        let portrait = try PDFPageOCR.render(page)
        XCTAssertEqual(portrait.height, PDFPageOCR.maximumDimension)
        XCTAssertLessThan(portrait.width, portrait.height)
        page.rotation = 90
        let rotatedDocument = try XCTUnwrap(PDFDocument(data: XCTUnwrap(document.dataRepresentation())))
        let landscape = try PDFPageOCR.render(XCTUnwrap(rotatedDocument.page(at: 0)))
        XCTAssertEqual(landscape.width, PDFPageOCR.maximumDimension)
        XCTAssertLessThan(landscape.height, landscape.width)
    }
}
