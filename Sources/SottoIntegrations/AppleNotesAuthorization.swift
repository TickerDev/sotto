import AppKit
import Carbon

/// Observation never launches Notes or requests consent. Only the explicit
/// connection action may launch it and show macOS's per-application prompt.
public enum AppleNotesAuthorization {
    public enum State: Sendable { case allowed, notRequested, denied, unavailable }
    public static func status() -> State { determine(ask: false) }
    private static func determine(ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
        switch result {
        case noErr: return .allowed
        case OSStatus(-1744), OSStatus(-600): return .notRequested
        case OSStatus(-1743): return .denied
        default: return .unavailable
        }
    }
    @MainActor public static func request() async -> State {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else { return .unavailable }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config) }
        catch { return .unavailable }
        return await Task.detached { determine(ask: true) }.value
    }
}
