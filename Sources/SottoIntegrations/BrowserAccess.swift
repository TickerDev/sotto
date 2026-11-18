import Foundation
import SottoTools

struct BrowserPageReference: Sendable, Equatable {
    let id: String
    let browser: String
    let title: String
    let url: String
    var arguments: [String: JSONValue] {
        ["page_ref": .string(id), "browser": .string(browser), "title": .string(title), "url": .string(url)]
    }
    var data: JSONValue { .object(arguments) }
}
struct BrowserPageLink: Sendable, Equatable {
    let id: Int
    let title: String
    let url: String
    var data: JSONValue { .object(["link_id": .number(Double(id)), "title": .string(title), "url": .string(url)]) }
}
struct BrowserPageExcerpt: Sendable {
    let reference: BrowserPageReference
    let text: String
    let links: [BrowserPageLink]
    let limited: Bool
    var data: JSONValue {
        .object(reference.arguments.merging([
            "text": .string(text), "links": .array(links.map(\.data)),
            "coverage": .string("Accessible page excerpt only; form controls are omitted. No claim of complete page content."),
            "limit_reached": .bool(limited), "untrusted_content": .bool(true)
        ]) { _, new in new })
    }
}
protocol BrowserAccess: Sendable {
    func capture() async throws -> BrowserPageReference
    func reference(_ id: String) async throws -> BrowserPageReference
    func validate(_ id: String) async throws
    func read(_ id: String) async throws -> BrowserPageExcerpt
    func link(_ id: String, index: Int) async throws -> BrowserPageLink
    /// OS URL handoff acceptance only; page loading is not verified.
    func open(_ id: String, index: Int, expectedURL: String) async throws -> Bool
}
enum BrowserPagePolicy {
    static let supportedBundles = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]
    static let excludedRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField", "AXSearchField",
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXSlider", "AXList"
    ]
    static func url(_ raw: String) throws -> URL {
        // Browser integration never fetches this URL. Apply the same conservative
        // public-HTTPS policy as browser opening, without reading cookies/credentials.
        try PublicWebPolicy.url(raw)
    }
    static func matches(_ text: String, query: String) throws -> JSONValue {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 200, !query.contains("\0") else { throw ToolError.invalid("Choose text of 1–200 characters to find") }
        var start = text.startIndex
        var matches: [JSONValue] = []
        while start < text.endIndex, matches.count < 10,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            let lower = text.index(range.lowerBound, offsetBy: -100, limitedBy: text.startIndex) ?? text.startIndex
            let upper = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
            matches.append(.object(["excerpt": .string(String(text[lower..<upper])), "offset": .number(Double(text.distance(from: text.startIndex, to: range.lowerBound)))]))
            start = range.upperBound
        }
        return .array(matches)
    }
}

/// Bounded accumulator shared by native extraction and safety fixtures. It only
/// accepts static text and actual accessible links, never editable field values.
struct BrowserExcerptBuilder {
    private(set) var text = ""
    private(set) var links: [BrowserPageLink] = []
    private var seenText: Set<String> = []
    private var seenURLs: Set<String> = []
    private(set) var limited = false
    mutating func append(role: String, value: String?, title: String?, url: String?) {
        if role == "AXStaticText", let value {
            let clean = String(value.prefix(16_001)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, seenText.insert(clean).inserted {
                let remaining = 16_000 - text.count
                if remaining > 0 {
                    let line = (text.isEmpty ? "" : "\n") + clean
                    text += line.prefix(remaining)
                    if line.count > remaining { limited = true }
                } else { limited = true }
            }
        }
        if role == "AXLink", let raw = url, let safe = try? BrowserPagePolicy.url(raw), seenURLs.insert(safe.absoluteString).inserted {
            if links.count < 50 { links.append(.init(id: links.count + 1, title: String((title ?? "").prefix(300)), url: safe.absoluteString)) }
            else { limited = true }
        }
    }
    mutating func markLimited() { limited = true }
}
