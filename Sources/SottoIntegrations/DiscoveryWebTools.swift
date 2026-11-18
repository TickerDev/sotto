import Foundation
import SottoTools

struct ImageSearchTool: Tool {
    let descriptor = ToolDescriptor(id: "web.images", description: "Search Wikimedia Commons images using its public API. Returns real thumbnails, originals, source pages, dimensions and available license metadata. Always inspect the source license before reuse.", properties: ["query": textProperty("Image topic"), "presentation": textProperty("single chooses a result to show inside Sotto; gallery shows several results", choices: ["single", "gallery"])], required: ["query"], risk: .read, capabilities: [.web])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let query = arguments.object?["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty, query.count <= 500 else { throw ToolError.invalid("Provide an image topic under 500 characters") }
        var c = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        let params = ["action": "query", "generator": "search", "gsrsearch": query, "gsrnamespace": "6", "gsrlimit": "12", "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "400", "format": "json"]
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, _) = try await PublicWebClient().get(c.url!, allowedMIME: ["application/json"])
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard json.object?["error"] == nil else { throw ToolError.unavailable("Image search service rejected the request") }
        let pages = json.object?["query"]?.object?["pages"]?.object ?? [:]
        let images: [JSONValue] = pages.values.compactMap { page in
            guard case .array(let infos) = page.object?["imageinfo"], let info = infos.first?.object,
                  let thumb = info["thumburl"]?.string, let original = info["url"]?.string,
                  let source = info["descriptionurl"]?.string,
                  ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(URL(string: thumb)?.host ?? ""), URL(string: original)?.host == "upload.wikimedia.org",
                  URL(string: source)?.host == "commons.wikimedia.org",
                  info["mime"]?.string?.hasPrefix("image/") == true else { return nil }
            let metadata = info["extmetadata"]?.object ?? [:]
            var row: [String: JSONValue] = [:]
            row["title"] = page.object?["title"] ?? .string("Image")
            row["thumbnail"] = .string(thumb); row["original"] = .string(original); row["source"] = .string(source)
            row["width"] = info["width"] ?? .null; row["height"] = info["height"] ?? .null
            row["mime"] = info["mime"] ?? .null
            row["license"] = .string(WebText.plain(metadata["LicenseShortName"]?.object?["value"]?.string ?? "License not supplied; inspect source"))
            row["license_url"] = metadata["LicenseUrl"]?.object?["value"] ?? .null
            row["artist"] = .string(WebText.plain(metadata["Artist"]?.object?["value"]?.string ?? ""))
            row["rank"] = page.object?["index"] ?? .number(0)
            return .object(row)
        }.sorted {
            guard case .number(let a) = $0.object?["rank"], case .number(let b) = $1.object?["rank"] else { return false }
            return a < b
        }
        let presentation = arguments.object?["presentation"]?.string ?? "single"
        return ToolResult(images.isEmpty ? "No matching images were found. Try a more specific subject." : "Found \(images.count) images. \(presentation == "single" ? "Selected the first ranked result for display inside Sotto." : "Showing the image results inside Sotto.")", data: .object(["images": .array(images), "selected_image": presentation == "single" ? (images.first ?? .null) : .null, "presentation": .string(presentation), "provider": .string("Wikimedia Commons"), "query": .string(query)]))
    }
}

struct DocumentSearchTool: Tool {
    let descriptor = ToolDescriptor(id: "web.documents", description: "Search scholarly publication metadata using Crossref’s public API. This is not general manual or PDF search. PDF links are returned only when supplied by the publisher and may require access rights.", properties: ["query": textProperty("Research topic"), "from_date": textProperty("Optional earliest publication date YYYY-MM-DD, or empty")], required: ["query", "from_date"], risk: .read, capabilities: [.web])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        let query = arguments.object?["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty, query.count <= 500 else { throw ToolError.invalid("Provide a research topic under 500 characters") }
        let date = arguments.object?["from_date"]?.string ?? ""
        if !date.isEmpty {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else { throw ToolError.invalid("Use a valid YYYY-MM-DD publication date") }
        }
        var c = URLComponents(string: "https://api.crossref.org/works")!
        c.queryItems = [URLQueryItem(name: "query.bibliographic", value: query), URLQueryItem(name: "rows", value: "10")]
        if !date.isEmpty { c.queryItems?.append(URLQueryItem(name: "filter", value: "from-pub-date:" + date)) }
        let (data, _) = try await PublicWebClient().get(c.url!, allowedMIME: ["application/json", "application/vnd.crossref-api-message+json"])
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .array(let items) = json.object?["message"]?.object?["items"] else { throw ToolError.unavailable("Publication search returned invalid metadata") }
        let documents: [JSONValue] = items.enumerated().compactMap { index, item in
            guard let object = item.object, case .array(let titles) = object["title"], let title = titles.first?.string,
                  let source = object["URL"]?.string, (try? PublicWebPolicy.url(source)) != nil else { return nil }
            var pdfs: [JSONValue] = []
            if case .array(let links) = object["link"] {
                pdfs = links.compactMap { link in
                    guard link.object?["content-type"]?.string == "application/pdf", let url = link.object?["URL"]?.string, (try? PublicWebPolicy.url(url)) != nil else { return nil }
                    return .string(url)
                }
            }
            return .object(["title": .string(title), "source": .string(source), "publisher": object["publisher"] ?? .null,
                "doi": object["DOI"] ?? .null, "published": object["published"] ?? .null, "type": object["type"] ?? .null,
                "pdf_urls": .array(pdfs), "rank": .number(Double(index + 1)), "access": .string("Availability and reuse rights are not verified")])
        }
        return ToolResult("Found \(documents.count) scholarly metadata records. Full-text/PDF access is not guaranteed.", data: .object(["documents": .array(documents), "provider": .string("Crossref"), "retrieved_at": .string(ISO8601DateFormatter().string(from: Date()))]))
    }
}
