import SwiftUI
import AppKit
import SottoIntegrations

struct LocalDocumentSettingsView: View {
    @AppStorage("automaticDocumentSearch") private var automatic = true
    @State private var status = ""
    @State private var excluded = UserDefaults.standard.stringArray(forKey: "documentSearchExcludedPaths") ?? []
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Your documents, ready to find") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Find documents automatically", isOn: $automatic)
                        .onChange(of: automatic) { _, _ in updateScope() }
                    Text("Just ask for a file or describe what it discusses. Sotto uses macOS search immediately and keeps a local content cache up to date in the background. No folders to choose or index to build.")
                        .font(.callout)
                    Text("Sotto can search files macOS makes accessible, including your user folders and available cloud documents. Protected locations may require access in System Settings. It cannot bypass macOS permissions.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    Text("Document excerpts and local meaning matching stay on this Mac. Opening a document for an AI answer follows your intelligence preferences. Content coverage depends on file format, macOS indexing and access; not every file’s contents can be extracted.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup("Exclude locations") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(excluded, id: \.self) { path in
                        HStack {
                            Text(path).font(.caption).textSelection(.enabled)
                            Spacer()
                            Button("Remove exclusion") {
                                excluded.removeAll { $0 == path }; persistExclusions()
                            }
                        }
                    }
                    Button("Exclude folder…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK, let path = panel.url?.path, !excluded.contains(path) {
                            excluded.append(path); persistExclusions()
                        }
                    }
                    Text("Exclusions apply to macOS search results, folder search and Sotto’s local cache.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }.task {
            while !Task.isCancelled {
                status = await LocalDocumentIndex.shared.status()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    private func persistExclusions() {
        UserDefaults.standard.set(excluded, forKey: "documentSearchExcludedPaths")
        updateScope()
    }
    private func updateScope() {
        Task {
            do { try await LocalDocumentIndex.shared.prune(); status = await LocalDocumentIndex.shared.status() }
            catch { self.error = error.localizedDescription }
        }
    }
}
