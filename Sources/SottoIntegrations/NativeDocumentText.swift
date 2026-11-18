import Foundation
@preconcurrency import AppKit
import SottoTools

struct NativeDocumentExcerpt: Sendable {
    let text: String
    let truncated: Bool
    let note: String
}
enum NativeDocumentText {
    static func decodeText(_ bytes: Data) throws -> String {
        let encoding: String.Encoding
        let payload: Data
        if bytes.starts(with: [0xff, 0xfe, 0x00, 0x00]) || bytes.starts(with: [0x00, 0x00, 0xfe, 0xff]) {
            throw ToolError.invalid("UTF-32 text is unsupported. Save a UTF-8 or UTF-16 copy.")
        } else if bytes.starts(with: [0xff, 0xfe]) {
            encoding = .utf16LittleEndian; payload = bytes.dropFirst(2)
        } else if bytes.starts(with: [0xfe, 0xff]) {
            encoding = .utf16BigEndian; payload = bytes.dropFirst(2)
        } else {
            encoding = .utf8; payload = bytes.starts(with: [0xef, 0xbb, 0xbf]) ? bytes.dropFirst(3) : bytes
        }
        guard (encoding == .utf8 || payload.count.isMultiple(of: 2)),
              let text = String(data: payload, encoding: encoding), !text.contains("\0"),
              text.data(using: encoding) == payload else {
            throw ToolError.invalid("This text encoding is unsupported or invalid. Use UTF-8, or UTF-16 with a byte-order marker.")
        }
        return text
    }
    static func extract(_ bytes: Data, kind: String, limit: Int) throws -> NativeDocumentExcerpt {
        try Task.checkCancellation()
        guard bytes.count <= DocumentTextReader.byteLimit, limit > 0, limit <= DocumentTextReader.textLimit else { throw ToolError.invalid("Document extraction exceeds its limit") }
        switch kind {
        case "txt", "md":
            let decoded = try decodeText(bytes)
            return NativeDocumentExcerpt(text: String(decoded.prefix(limit)), truncated: decoded.count > limit,
                                         note: "UTF-8 or BOM-marked UTF-16 text extraction; disclose truncation.")
        case "rtf":
            guard bytes.count <= 2_000_000, bytes.starts(with: Data(#"{\rtf1"#.utf8)) else { throw ToolError.invalid("Choose a valid RTF document under 2 MB") }
            let source = String(decoding: bytes, as: UTF8.self)
            guard source.range(of: #"\\(?:object|objdata|pict|filetbl|field|bin)(?:[^a-zA-Z]|$)"#, options: [.regularExpression, .caseInsensitive]) == nil else {
                throw ToolError.denied("RTF documents with fields, pictures, binary data or embedded objects are unsupported. Export a PDF or text copy to read it safely.")
            }
            guard let rich = NSAttributedString(rtf: bytes, documentAttributes: nil) else { throw ToolError.unavailable("This rich-text document could not be read") }
            try Task.checkCancellation()
            let text = rich.string.replacingOccurrences(of: "\u{fffc}", with: "")
            return NativeDocumentExcerpt(text: String(text.prefix(limit)), truncated: text.count > limit,
                                         note: "Native RTF text only; formatting is not preserved. Documents with fields, images, binary data or embedded objects are refused. Disclose truncation.")
        case "docx":
            let archive = try DocumentZIP(bytes)
            let types = try archive.read("[Content_Types].xml")
            guard types.count <= 512_000 else { throw ToolError.invalid("Word document type metadata exceeds its limit") }
            let content = ContentTypesDelegate()
            let typeParser = try parser(types, delegate: content)
            let validType = typeParser.parse()
            try Task.checkCancellation()
            guard validType, content.standardDocument, !content.forbidden else { throw ToolError.invalid("Only standard DOCX documents are supported; encrypted or macro-enabled formats are unavailable") }
            let xml = try archive.read("word/document.xml")
            let document = WordTextDelegate(limit: limit)
            let reader = try parser(xml, delegate: document)
            let parsed = reader.parse()
            try Task.checkCancellation()
            guard !document.cancelled, parsed || document.truncated, document.hasDocumentBody else {
                if document.cancelled { throw CancellationError() }
                throw ToolError.invalid("The Word document XML is invalid or unsupported")
            }
            return NativeDocumentExcerpt(text: document.text.trimmingCharacters(in: .whitespacesAndNewlines), truncated: document.truncated,
                                         note: "DOCX main-body text in document order, including table text. Headers, footers, comments, deleted/explicitly hidden runs, images, embedded objects and linked resources are omitted. Style-inherited visibility, pagination and layout are not resolved; disclose omissions and truncation.")
        default: throw ToolError.invalid("This document format is unsupported")
        }
    }
    private static func parser(_ bytes: Data, delegate: XMLParserDelegate) throws -> XMLParser {
        let xml = try decodeText(bytes)
        guard xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw ToolError.denied("XML declarations with DTDs or entities are not supported") }
        let parser = XMLParser(data: bytes)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        return parser
    }
}
private final class ContentTypesDelegate: NSObject, XMLParserDelegate {
    var standardDocument = false
    var forbidden = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if Task.isCancelled { parser.abortParsing(); return }
        guard namespaceURI == "http://schemas.openxmlformats.org/package/2006/content-types", name == "Override" else { return }
        if attributes["PartName"] == "/word/document.xml" {
            if standardDocument { forbidden = true }
            standardDocument = attributes["ContentType"] == "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
            if !standardDocument { forbidden = true }
        }
    }
}
private final class WordTextDelegate: NSObject, XMLParserDelegate {
    let limit: Int
    var text = "", truncated = false, cancelled = false, hasDocumentBody = false
    private var stack: [(String, String?)] = []
    private var textDepth: Int?
    private var bodyDepth: Int?
    private var ignoredDepth: Int?
    private var hiddenRunDepth: Int?
    private let namespaces: Set<String> = ["http://schemas.openxmlformats.org/wordprocessingml/2006/main", "http://purl.oclc.org/ooxml/wordprocessingml/main"]
    init(limit: Int) { self.limit = limit }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if Task.isCancelled { cancelled = true; parser.abortParsing(); return }
        stack.append((name, namespaceURI))
        guard stack.count <= 128 else { parser.abortParsing(); return }
        guard let namespaceURI, namespaces.contains(namespaceURI) else { return }
        if name == "body", stack.count == 2, stack.first?.0 == "document", stack.first?.1 == namespaceURI {
            bodyDepth = stack.count; hasDocumentBody = true
        }
        guard bodyDepth != nil else { return }
        if ["del", "moveFrom", "drawing", "object", "txbxContent", "altChunk"].contains(name), ignoredDepth == nil { ignoredDepth = stack.count }
        if name == "vanish" || name == "webHidden" {
            let disabled = attributes.first { $0.key == "val" || $0.key.hasSuffix(":val") }?.value
            if !["false", "0", "off"].contains(disabled ?? ""), let run = stack.lastIndex(where: { $0.0 == "r" && $0.1 == namespaceURI }) { hiddenRunDepth = run + 1 }
        }
        guard ignoredDepth == nil, hiddenRunDepth == nil else { return }
        if name == "t" { textDepth = stack.count }
        if name == "tab" { append("\t", parser: parser) }
        if name == "br" || name == "cr" { append("\n", parser: parser) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard textDepth != nil, ignoredDepth == nil, hiddenRunDepth == nil else { return }
        append(string, parser: parser)
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if let namespaceURI, namespaces.contains(namespaceURI), bodyDepth != nil, ignoredDepth == nil, hiddenRunDepth == nil {
            if name == "p" || name == "tr" { append("\n", parser: parser) }
            if name == "tc" { append("\t", parser: parser) }
        }
        if textDepth == stack.count { textDepth = nil }
        if ignoredDepth == stack.count { ignoredDepth = nil }
        if hiddenRunDepth == stack.count { hiddenRunDepth = nil }
        if bodyDepth == stack.count { bodyDepth = nil }
        if !stack.isEmpty { stack.removeLast() }
    }
    private func append(_ value: String, parser: XMLParser) {
        if Task.isCancelled { cancelled = true; parser.abortParsing(); return }
        let remaining = limit - text.count
        text += value.prefix(max(0, remaining))
        if value.count > remaining { truncated = true; parser.abortParsing() }
    }
}
