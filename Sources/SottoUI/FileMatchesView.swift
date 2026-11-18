import AppKit
import SwiftUI
import SottoTools

/// Results come from the native search tool, never from model-authored prose.
struct FileMatchesView: View {
    let matches: [FileSearchMatch]
    let select: (FileSearchMatch, Bool) -> Void
    var summarize: ((FileSearchMatch) -> Void)? = nil
    @State private var listHeight: CGFloat = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best matches").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(matches) { match in
                        HStack(spacing: 8) {
                            Button { select(match, false) } label: {
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: match.path)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(match.name).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        Text((URL(fileURLWithPath: match.path).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        if let date = match.modified { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 8).padding(.horizontal, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Open \(match.path)").accessibilityLabel("Open \(match.name)")
                                .accessibilityValue(URL(fileURLWithPath: match.path).deletingLastPathComponent().path)
                            if DocumentTextFormats.supports(match.path), let summarize {
                                Button("Summarize") { summarize(match) }
                                    .buttonStyle(.borderless).controlSize(.small).font(.system(size: 11)).help("Summarize \(match.name)")
                                    .accessibilityLabel("Summarize \(match.name)")
                                    .accessibilityHint("Uses your selected intelligence to summarize this document")
                            }
                            Button { select(match, true) } label: { Image(systemName: "folder").frame(width: 24, height: 28) }
                                .buttonStyle(.borderless).help("Show in Finder").accessibilityLabel("Show \(match.name) in Finder")
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in Color.clear.preference(key: FileResultsHeight.self, value: proxy.size.height) })
            }.frame(height: min(max(1, listHeight), 264)).scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(FileResultsHeight.self) { if $0.isFinite && $0 > 0 { listHeight = $0 } }
            Text(summarize == nil ? "Click a file to open it, or use the folder button to show it in Finder." : "Open a file, summarize supported documents, or show it in Finder.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FileResultsHeight: PreferenceKey {
    static let defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
