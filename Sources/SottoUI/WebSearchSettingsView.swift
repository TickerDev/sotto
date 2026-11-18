import SwiftUI

struct WebSearchSettingsView: View {
    @AppStorage("webSearchDailyLimit") private var dailyLimit = 50
    @State private var connection = WebSearchConnectionModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Search without setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Searches run inside Sotto without opening Chrome or another browser. Pictures, Wikipedia results and scholarly publication metadata work without a connection. Connect general web answers below to search the wider web headlessly.")
                    Text("Sotto does not read your browser tabs or signed-in websites. A browser opens only when you ask to open a website or search in a browser.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Web answers inside Sotto") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect your own Brave Search plan to see website results and source links here. Search queries are sent to Brave. Research can make up to two searches per request.")
                    Stepper("Daily request limit on this Mac: \(dailyLimit)", value: $dailyLimit, in: 1...500)
                    Text("Requests are counted before sending, including connection tests and failed attempts. The counter resets at midnight UTC; this does not limit usage from other apps or replace account billing limits.").font(.caption).foregroundStyle(.secondary)
                    Text(connection.status).font(.callout).textSelection(.enabled)
                        .accessibilityIdentifier("web-connection-status")
                    DisclosureGroup("Connect a search service") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("A Brave Search account and access key are required. Usage may cost money under your plan. Connecting sends one test search; later searches and research use that connection until you disconnect.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Link("Get access", destination: URL(string: "https://api-dashboard.search.brave.com/")!)
                                Link("Current plans and pricing", destination: URL(string: "https://brave.com/search/api/")!)
                            }
                            SecureField("Brave Search access key", text: $connection.key)
                                .textContentType(.password).disabled(connection.busy)
                            HStack {
                                Button("Connect and test") { Task { await connection.connect() } }
                                    .disabled(connection.busy || connection.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Disconnect") { Task { await connection.disconnect() } }.disabled(connection.busy)
                                if connection.busy { ProgressView().controlSize(.small) }
                            }
                            Text("The key stays in this Mac’s Keychain. It is never sent to your reasoning provider or included in activity logs.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Reading and research") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ask Sotto to compare up to three website links. It returns source excerpts and identifies inaccessible sources. Page retrieval currently supports selected public publishers.")
                    Text("Source diversity is not proof of independent evidence. Sotto reports missing dates and distinguishes search snippets from pages it actually read.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await connection.inspect() }
    }
}
