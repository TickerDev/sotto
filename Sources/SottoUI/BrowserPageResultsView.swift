import SwiftUI
import SottoTools
import SottoIntegrations

/// Provenance comes from the native result, never from model-authored links.
struct BrowserPageResultsView: View {
    let page: JSONValue
    let answer: String
    let openLink: (String, Int) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !answer.isEmpty { Text(answer).font(.system(size: 12)).textSelection(.enabled) }
                if let raw = page.object?["url"]?.string, let url = try? PublicWebPolicy.url(raw) {
                    Link(destination: url) {
                        Text(page.object?["title"]?.string ?? url.host ?? "Source page")
                            .font(.system(size: 12, weight: .medium)).multilineTextAlignment(.leading)
                    }
                    .help(url.absoluteString)
                    .accessibilityLabel("Open source page: " + (page.object?["title"]?.string ?? url.host ?? "website"))
                    Text(url.host ?? "").font(.caption2).foregroundStyle(.secondary)
                }
                if let coverage = page.object?["coverage"]?.string {
                    Text(coverage).font(.caption).foregroundStyle(.secondary)
                }
                if let text = page.object?["text"]?.string, !text.isEmpty {
                    DisclosureGroup("Read the extracted excerpt") {
                        Text(text).font(.system(size: 12)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }.font(.caption)
                }
                if let reference = page.object?["page_ref"]?.string,
                   case .array(let links) = page.object?["links"], !links.isEmpty {
                    DisclosureGroup("Links from this page") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(links.prefix(50).enumerated()), id: \.offset) { _, link in
                                if let object = link.object, let raw = object["url"]?.string,
                                   let url = try? PublicWebPolicy.url(raw), case .number(let index) = object["link_id"],
                                   index >= 1, index <= 50, index.rounded() == index {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Button {
                                            openLink(reference, Int(index))
                                        } label: {
                                            Text((object["title"]?.string?.isEmpty == false ? object["title"]?.string : nil) ?? url.absoluteString)
                                                .multilineTextAlignment(.leading)
                                        }
                                        .help("Review before opening " + url.absoluteString)
                                        .accessibilityHint("Reviews this link destination before opening it in your default browser.")
                                        Text(url.host ?? "").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 320)
    }
}
