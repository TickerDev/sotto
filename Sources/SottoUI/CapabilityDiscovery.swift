import AppKit
import Speech
import EventKit
import Observation
import SottoProviders
import SottoAudio

public enum CapabilityAvailability: String, Sendable { case ready, permissionRequired, setupRequired, unavailable }
public struct DiscoveredCapability: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let state: CapabilityAvailability
    public let detail: String
}
public struct DeviceCapabilities: Sendable {
    public let osVersion: String
    public let memoryBytes: UInt64
    public let appleSilicon: Bool
    public let onDeviceReasoning: Bool
    public let onDeviceSpeech: Bool
    public let speechAvailable: Bool
    public let installedApplications: [String]
    public let capabilities: [DiscoveredCapability]
}

/// Observation only: no permission prompts, app launches, audio capture or external requests.
@MainActor @Observable public final class CapabilityDiscovery {
    public private(set) var snapshot: DeviceCapabilities?
    public init() {}
    public func refresh(language: String, permissions: PermissionCenter, speechBackend: SpeechBackend = .apple, remoteSpeechConfigured: Bool = false, modernSpeechReady: Bool = false) {
        let supportedApps = ["com.apple.finder", "com.apple.reminders", "com.apple.iCal", "com.spotify.client"]
        let installed = supportedApps.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
        #if arch(arm64)
        let silicon = true
        #else
        let silicon = false
        #endif
        let voice = speechBackend == .apple
            ? DiscoveredCapability(id: "speech", title: "Listen to your requests", state: modernSpeechReady ? (permissions.state(.microphone) == .allowed ? .ready : .permissionRequired) : recognizer?.isAvailable == true ? (permissions.voiceAllowed ? .ready : .permissionRequired) : .unavailable, detail: modernSpeechReady ? "Modern live transcription is ready on this Mac. Only microphone access is needed." : recognizer?.supportsOnDeviceRecognition == true ? "On-device speech is supported for your language." : "On-device speech is unavailable for your language. Review Voice settings.")
            : DiscoveredCapability(id: "speech", title: "Listen with OpenAI Realtime", state: !remoteSpeechConfigured ? .setupRequired : permissions.state(.microphone) == .allowed ? .ready : .permissionRequired, detail: "Streams audio to OpenAI while you explicitly listen. Requires audio permission, an API key, network and account access; configured in Voice.")
        var capabilities = [
            DiscoveredCapability(id: "folders", title: "Open your folders", state: .ready, detail: "Works on this Mac without an AI connection."),
            DiscoveredCapability(id: "calendar", title: "See what’s on your calendar", state: permissions.state(.calendar) == .allowed ? .ready : .permissionRequired, detail: "Ask “What’s on my calendar tomorrow?” No AI connection needed. Sotto asks for access the first time and never changes events."),
            DiscoveredCapability(id: "files", title: "Find files", state: .ready, detail: "Searches Spotlight’s index. Results depend on indexing and file access."),
            DiscoveredCapability(id: "apps", title: "Open applications", state: .ready, detail: "Uses installed applications. Natural-language requests need intelligence."),
            DiscoveredCapability(id: "reminders", title: "Access your reminders", state: permissions.state(.reminders) == .allowed ? .ready : .permissionRequired, detail: permissions.state(.reminders) == .allowed ? "Access allowed; a writable list is needed to create reminders." : "Sotto asks for access when you request a reminder."),
            voice
        ]
        if installed.contains("com.spotify.client") {
            capabilities.append(DiscoveredCapability(id: "music", title: "Control music in Spotify", state: .permissionRequired, detail: "Installed. macOS asks for automation access on first use; sign-in and playback availability are checked when used."))
        }
        snapshot = DeviceCapabilities(osVersion: ProcessInfo.processInfo.operatingSystemVersionString, memoryBytes: ProcessInfo.processInfo.physicalMemory, appleSilicon: silicon, onDeviceReasoning: OnDeviceIntelligence.available, onDeviceSpeech: recognizer?.supportsOnDeviceRecognition == true, speechAvailable: recognizer?.isAvailable == true, installedApplications: installed, capabilities: capabilities)
    }
}
