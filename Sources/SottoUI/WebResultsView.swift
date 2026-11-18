import SwiftUI
import SottoIntegrations

/// Native links never interpret model-authored Markdown as executable actions.
struct WebResultsView: View {
    let results: [WebSearchResult]
    var provider = "Wikipedia"
    var scope = "Encyclopedia search"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(provider + " results").font(.system(size: 12, weight: .semibold))
            Text(scope)
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 5) {
                            if let url = try? PublicWebPolicy.url(result.url) {
                                Link(destination: url) {
                                    Label(result.title, systemImage: "arrow.up.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .multilineTextAlignment(.leading)
                                }
                                .accessibilityLabel("Open \(result.title) on \(result.domain)")
                                .help(url.absoluteString)
                            }
                            Text(result.domain).font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(result.description).font(.system(size: 12)).textSelection(.enabled)
                            if let date = result.pageDate {
                                Text("Reported page date (published or updated): \(date)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            if let published = result.published {
                                Text("Reported page date: \(published)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            if let freshness = result.freshness {
                                Text("Reported age: \(freshness)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            if let modified = result.modified {
                                Text("Page edited: \(modified)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.trailing, 4)
            }.frame(maxHeight: 280)
        }
    }
}

import SottoTools

struct ImageResultsView: View {
    let images: [JSONValue]
    let save: (String) -> Void
    @State private var preview: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Images from Wikimedia Commons").font(.system(size: 12, weight: .semibold))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 14) {
                    ForEach(images.indices, id: \.self) { index in
                        let item = images[index].object ?? [:]
                        VStack(alignment: .leading, spacing: 6) {
                            Button { preview = index } label: {
                                AsyncImage(url: thumbnail(item)) { image in image.resizable().scaledToFit() } placeholder: {
                                    Label("Loading image", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
                                }.frame(height: 100).frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).accessibilityLabel("Preview \(item["title"]?.string ?? "image")")
                            Text(item["title"]?.string ?? "Image").font(.caption).lineLimit(2)
                            Text(item["license"]?.string ?? "Review source license").font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                if let source = safeURL(item["source"]?.string) { Link("Source", destination: source) }
                                if let original = item["original"]?.string { Button("Save…") { save(original) } }
                            }.font(.caption)
                        }
                    }
                }
            }.frame(maxHeight: 300)
            Text("Check attribution and license terms on the source page before reuse.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let index = preview, images.indices.contains(index) {
                let item = images[index].object ?? [:]
                VStack(alignment: .leading, spacing: 12) {
                    Text(item["title"]?.string ?? "Image").font(.headline)
                    AsyncImage(url: thumbnail(item)) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 260)
                    Text(item["license"]?.string ?? "Inspect the source license").font(.caption)
                    Text(item["artist"]?.string ?? "").font(.caption).textSelection(.enabled)
                    HStack {
                        if let original = safeURL(item["original"]?.string) { Link("Open original", destination: original) }
                        if let source = safeURL(item["source"]?.string) { Link("Open source", destination: source) }
                        Spacer()
                        Button("Done") { preview = nil }.keyboardShortcut(.cancelAction)
                    }
                }.padding(20).frame(width: 420)
            }
        }
    }
    private func safeURL(_ value: String?) -> URL? { value.flatMap { try? PublicWebPolicy.url($0) } }
    private func thumbnail(_ item: [String: JSONValue]) -> URL? {
        guard let url = safeURL(item["thumbnail"]?.string), ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(url.host ?? "") else { return nil }
        return url
    }
}

struct DocumentResultsView: View {
    let documents: [JSONValue]
    let download: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scholarly publications").font(.system(size: 12, weight: .semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(documents.indices, id: \.self) { index in
                        let item = documents[index].object ?? [:]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item["title"]?.string ?? "Publication").font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                            Text(item["publisher"]?.string ?? "Publisher not supplied").font(.caption).foregroundStyle(.secondary)
                            Text(item["type"]?.string ?? "Publication").font(.caption2).foregroundStyle(.secondary)
                            if let date = publicationDate(item["published"]) { Text(date).font(.caption2).foregroundStyle(.secondary) }
                            HStack {
                                if let source = item["source"]?.string, let url = try? PublicWebPolicy.url(source) { Link("Open source", destination: url) }
                                if case .array(let pdfs) = item["pdf_urls"], let pdf = pdfs.first?.string { Button("Download PDF…") { download(pdf) } }
                            }.font(.caption)
                            Text(item["access"]?.string ?? "").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(maxHeight: 280)
            Text("Crossref metadata · Full text may require access rights. Downloads support selected publishers.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func publicationDate(_ value: JSONValue?) -> String? {
        guard case .array(let parts) = value?.object?["date-parts"], case .array(let date) = parts.first else { return nil }
        return date.compactMap { if case .number(let n) = $0 { return String(Int(n)) }; return nil }.joined(separator: "-")
    }
}

struct ResearchResultsView: View {
    let sources: [JSONValue]
    let answer: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !answer.isEmpty {
                    Text(answer).font(.system(size: 12)).textSelection(.enabled)
                }
                Text("Sources").font(.system(size: 12, weight: .semibold))
                ForEach(sources.indices, id: \.self) { index in
                    let source = sources[index].object ?? [:]
                    VStack(alignment: .leading, spacing: 5) {
                        if let raw = source["url"]?.string, let url = try? PublicWebPolicy.url(raw) {
                            Link(destination: url) {
                                Text((source["citation"]?.string ?? "Source") + " · " + (source["title"]?.string ?? url.host ?? "Website"))
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.leading)
                            }.help(url.absoluteString)
                                .accessibilityLabel("Open source \(index + 1): \(source["title"]?.string ?? url.host ?? "website")")
                            Text(url.host ?? "").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(source["evidence_kind"]?.string == "search_snippet" ? "Search snippet · Full page was not read" : "Retrieved page excerpt")
                            .font(.caption).foregroundStyle(.secondary)
                        if let date = source["published"]?.string {
                            Text("Reported publication date: " + date).font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("Publication date not supplied").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let date = source["reported_page_date"]?.string {
                            Text("Reported page date (published or updated): " + date).font(.caption2).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Read evidence") {
                            Text(source["text"]?.string ?? "").font(.system(size: 12)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }.font(.caption)
                    }
                }
                Text("Sources may share underlying evidence. Compare their claims and check the original pages.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 320)
    }
}
