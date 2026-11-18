import AppKit
import Carbon

/// Only these reviewed application targets can enter the native connection flow.
public enum ApplicationAutomationAuthorization {
    public enum Target: Sendable {
        case appleNotes, appleMail
        var bundleID: String { switch self { case .appleNotes: "com.apple.Notes"; case .appleMail: "com.apple.mail" } }
    }
    public enum State: Sendable { case allowed, notRequested, denied, unavailable }
    public static func status(_ target: Target) -> State { determine(target, ask: false) }
    private static func determine(_ target: Target, ask: Bool) -> State {
        let address = NSAppleEventDescriptor(bundleIdentifier: target.bundleID)
        let result = AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, ask)
        switch result {
        case noErr: return .allowed
        case OSStatus(-1744), OSStatus(-600): return .notRequested
        case OSStatus(-1743): return .denied
        default: return .unavailable
        }
    }
    @MainActor public static func request(_ target: Target) async -> State {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID) else { return .unavailable }
        let config = NSWorkspace.OpenConfiguration(); config.activates = false
        do { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config) }
        catch { return .unavailable }
        return await Task.detached { determine(target, ask: true) }.value
    }
}
public enum AppleMailAuthorization {
    public typealias State = ApplicationAutomationAuthorization.State
    public static func status() -> State { ApplicationAutomationAuthorization.status(.appleMail) }
    @MainActor public static func request() async -> State { await ApplicationAutomationAuthorization.request(.appleMail) }
}
