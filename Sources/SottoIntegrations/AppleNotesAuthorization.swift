import Foundation

/// Compatibility facade for Notes' existing permission and acceptance flow.
public enum AppleNotesAuthorization {
    public typealias State = ApplicationAutomationAuthorization.State
    public static func status() -> State { ApplicationAutomationAuthorization.status(.appleNotes) }
    @MainActor public static func request() async -> State { await ApplicationAutomationAuthorization.request(.appleNotes) }
}
