import SwiftUI
import SottoTools
import SottoIntegrations

/// Presents an actual search result inside the capsule, not a browser handoff.
struct FeaturedImageView: View {
    let images: [JSONValue]
    let save: (String) -> Void
    var showGalleryInitially = false
    @State private var selected = 0
    @State private var gallery = false
    var body: some View {
        if gallery || showGalleryInitially {
            ImageResultsView(images: images, save: save)
        } else if images.indices.contains(selected) {
            let item = images[selected].object ?? [:]
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: thumbnail(item)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .accessibilityLabel(item["title"]?.string ?? "Selected image result")
                    case .failure:
                        VStack(spacing: 8) {
                            Label("This picture couldn’t load", systemImage: "photo")
                            if selected + 1 < images.count { Button("Try another picture") { selected += 1 } }
                        }.font(.caption).frame(maxWidth: .infinity, minHeight: 140)
                    case .empty: ProgressView("Loading picture").frame(maxWidth: .infinity, minHeight: 140)
                    @unknown default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity).frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text((item["title"]?.string ?? "Picture").replacingOccurrences(of: "File:", with: ""))
                    .font(.system(size: 12, weight: .medium)).lineLimit(2)
                HStack(spacing: 14) {
                    if let source = safeURL(item["source"]?.string) {
                        Link("Source", destination: source).help(source.absoluteString)
                    }
                    Button("Other pictures") { gallery = true }
                    if let original = item["original"]?.string { Button("Save…") { save(original) } }
                }.font(.caption)
                DisclosureGroup("Image details") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item["license"]?.string ?? "Review licensing on the source page")
                        if let artist = item["artist"]?.string, !artist.isEmpty { Text(artist) }
                        if let original = safeURL(item["original"]?.string) { Link("Open full image", destination: original) }
                    }.font(.caption).textSelection(.enabled)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func safeURL(_ raw: String?) -> URL? { raw.flatMap { try? PublicWebPolicy.url($0) } }
    private func thumbnail(_ item: [String: JSONValue]) -> URL? {
        guard let url = safeURL(item["thumbnail"]?.string),
              ["upload.wikimedia.org", "thumb.wikimedia.org"].contains(url.host ?? "") else { return nil }
        return url
    }
}
