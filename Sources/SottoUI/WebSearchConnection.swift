import Foundation
import Observation
import SottoIntegrations
import SottoSecurity

/// Search and reasoning credentials have separate Keychain accounts.
enum WebSearchConnection {
    static let credentials = KeychainCredentials(account: "brave_search")
    static var provider: BraveSearchProvider {
        BraveSearchProvider(key: { try await credentials.read() }, enabled: { UserDefaults.standard.bool(forKey: "webAnswersEnabled") })
    }
}

@MainActor @Observable final class WebSearchConnectionModel {
    var key = ""
    private(set) var busy = false
    private(set) var status = ""
    var connected: Bool { UserDefaults.standard.bool(forKey: "webAnswersEnabled") }
    func inspect() async {
        do {
            let saved = try await WebSearchConnection.credentials.containsKey()
            status = saved && connected ? "Connected to Brave Search. Searches use your plan." : "Pictures and Wikipedia search work inside Sotto without a connection."
        } catch { status = error.localizedDescription }
    }
    func connect() async {
        guard !busy else { return }
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { status = "Enter your Brave Search access key."; return }
        busy = true
        defer { busy = false }
        do {
            let provider = BraveSearchProvider(key: { candidate })
            _ = try await provider.search(query: "Swift programming language", offset: 0)
            try Task.checkCancellation()
            try await WebSearchConnection.credentials.save(candidate)
            UserDefaults.standard.set(true, forKey: "webAnswersEnabled")
            key = ""
            status = "Connected to Brave Search. Searches use your plan."
        } catch is CancellationError { status = "Connection test cancelled." }
        catch { status = error.localizedDescription }
    }
    func disconnect() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        // Disable requests even if Keychain removal subsequently fails.
        UserDefaults.standard.set(false, forKey: "webAnswersEnabled")
        do { try await WebSearchConnection.credentials.save(""); key = ""; status = "Disconnected. Pictures and Wikipedia remain available inside Sotto." }
        catch { status = "Search is disabled. The saved key could not be removed: " + error.localizedDescription }
    }
}
