import AppKit
import AVFoundation
import Speech
import EventKit
import Observation
import SottoAudio
import IOKit.hidsystem
import OSLog

public enum PermissionKind: String, CaseIterable, Sendable, Identifiable {
    case microphone, speech, keyboard, reminders, calendar, automation
    public var id: String { rawValue }
    public var title: String {
        switch self { case .microphone: "Microphone"; case .speech: "Speech Recognition"; case .keyboard: "Input Monitoring"; case .reminders: "Reminders"; case .calendar: "Calendar"; case .automation: "Spotify Automation" }
    }
    public var detail: String {
        switch self {
        case .microphone: "Captures audio only when you start listening."
        case .speech: "Needed for older Apple Speech recognition. Modern on-device transcription and OpenAI Realtime use microphone permission instead."
        case .keyboard: "Enables your global shortcut. Optional when using the menu bar."
        case .reminders: "Requested when you first create or list reminders."
        case .calendar: "Requested when you ask about your calendar. Sotto does not change events."
        case .automation: "Requested by a Spotify command. macOS manages access per application."
        }
    }
    public var settingsURL: URL {
        let pane: String
        switch self { case .microphone: pane = "Privacy_Microphone"; case .speech: pane = "Privacy_SpeechRecognition"; case .keyboard: pane = "Privacy_ListenEvent"; case .reminders: pane = "Privacy_Reminders"; case .calendar: pane = "Privacy_Calendars"; case .automation: pane = "Privacy_Automation" }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}
public enum PermissionState: String, Sendable {
    case allowed, notRequested, notEnabled, denied, restricted, systemManaged, unavailable
    public var label: String {
        switch self { case .allowed: "Allowed"; case .notRequested: "Not requested"; case .notEnabled: "Not enabled"; case .denied: "Not allowed"; case .restricted: "Restricted by your Mac"; case .systemManaged: "Managed by macOS"; case .unavailable: "Unavailable to this copy" }
    }
    public var canRequest: Bool { self == .notRequested || self == .notEnabled }
}
public enum PermissionRequestOutcome: Sendable, Equatable {
    case allowed, notGranted, settingsRequired, unavailable, busy
    static func afterRequest(state: PermissionState, returnedError: Bool = false) -> Self {
        if state == .allowed { return .allowed }
        if returnedError { return .unavailable }
        if state == .denied || state == .restricted { return .notGranted }
        return .unavailable
    }
}
struct KeyboardPermissionSnapshot: Equatable {
    enum Decision: Equatable { case granted, denied, unknown }
    var preflightGranted: Bool
    var decision: Decision
    var listenerReady: Bool
    var state: PermissionState {
        if preflightGranted || listenerReady { return .allowed }
        return decision == .unknown ? .notRequested : .unavailable
    }
    var shortcutLabel: String {
        if listenerReady { return "Ready" }
        if state == .allowed { return "Shortcut unavailable · retry registration" }
        return state == .notRequested ? "Needs Input Monitoring" : "Keyboard access unavailable"
    }
}
@MainActor @Observable public final class PermissionCenter {
    public private(set) var states: [PermissionKind: PermissionState] = [:]
    public private(set) var requesting: PermissionKind?
    public var changed: (() -> Void)?
    var keyboardListenerReady: () -> Bool = { false }
    public var restartApplication: (() -> Void)?
    private(set) var keyboard = KeyboardPermissionSnapshot(preflightGranted: false, decision: .unknown, listenerReady: false)
    public init() { refresh() }
    public func state(_ kind: PermissionKind) -> PermissionState { states[kind] ?? .notRequested }
    public var voiceAllowed: Bool { state(.microphone) == .allowed && state(.speech) == .allowed }
    public func refresh() {
        states[.microphone] = switch AVCaptureDevice.authorizationStatus(for: .audio) { case .authorized: .allowed; case .denied: .denied; case .restricted: .restricted; default: .notRequested }
        states[.speech] = switch SFSpeechRecognizer.authorizationStatus() { case .authorized: .allowed; case .denied: .denied; case .restricted: .restricted; default: .notRequested }
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let snapshot = KeyboardPermissionSnapshot(preflightGranted: CGPreflightListenEventAccess(), decision: access == kIOHIDAccessTypeGranted ? .granted : access == kIOHIDAccessTypeDenied ? .denied : .unknown, listenerReady: keyboardListenerReady())
        if keyboard != snapshot {
            Logger(subsystem: "org.sotto.mac", category: "keyboard").notice("Keyboard access: preflight=\(snapshot.preflightGranted), HID=\(access.rawValue), listener=\(snapshot.listenerReady)")
        }
        keyboard = snapshot
        states[.keyboard] = snapshot.state
        states[.reminders] = switch EKEventStore.authorizationStatus(for: .reminder) { case .fullAccess: .allowed; case .denied: .denied; case .restricted: .restricted; default: .notRequested }
        states[.calendar] = Self.calendarState(EKEventStore.authorizationStatus(for: .event))
        states[.automation] = .systemManaged
        changed?()
    }
    static func calendarState(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status { case .fullAccess: .allowed; case .denied: .denied; case .restricted: .restricted; default: .notRequested }
    }
    @discardableResult public func request(_ kind: PermissionKind) async -> PermissionRequestOutcome {
        guard requesting == nil else { return .busy }
        refresh()
        if state(kind) == .allowed { return .allowed }
        guard state(kind).canRequest else { openSettings(kind); return .settingsRequired }
        requesting = kind
        defer { requesting = nil }
        var requestFailed = false
        switch kind {
        case .microphone: _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speech: _ = await SpeechAuthorization.request()
        case .keyboard: if !CGRequestListenEventAccess() { openSettings(kind) }
        case .reminders:
            do { _ = try await EKEventStore().requestFullAccessToReminders() } catch { requestFailed = true }
        case .calendar:
            do { _ = try await EKEventStore().requestFullAccessToEvents() } catch { requestFailed = true }
        case .automation: openSettings(kind)
        }
        refresh()
        return PermissionRequestOutcome.afterRequest(state: state(kind), returnedError: requestFailed)
    }
    public func openSettings(_ kind: PermissionKind) {
        if !NSWorkspace.shared.open(kind.settingsURL) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
    }
}
public struct SetupReadiness: Sendable {
    public let nativeActionsAvailable: Bool
    public let providerConnected: Bool
    public let remoteConsent: Bool
    public let voiceAllowed: Bool
    public let microphoneAvailable: Bool
    public let shortcutReady: Bool
    public init(providerConnected: Bool, remoteConsent: Bool, voiceAllowed: Bool, microphoneAvailable: Bool, shortcutReady: Bool, nativeActionsAvailable: Bool = false) {
        self.nativeActionsAvailable = nativeActionsAvailable
        self.providerConnected = providerConnected; self.remoteConsent = remoteConsent; self.voiceAllowed = voiceAllowed; self.microphoneAvailable = microphoneAvailable; self.shortcutReady = shortcutReady
    }
    public var ready: Bool { nativeActionsAvailable || (providerConnected && remoteConsent && voiceAllowed && microphoneAvailable) }
    public var completedSteps: Int { [providerConnected, remoteConsent, voiceAllowed && microphoneAvailable, shortcutReady].filter { $0 }.count }
    public var blockers: [String] {
        if nativeActionsAvailable { return [] }
        var result: [String] = []
        if !providerConnected { result.append("Connect and verify your AI provider.") }
        if !remoteConsent { result.append("Choose whether to allow requests to OpenAI.") }
        if !voiceAllowed { result.append("Allow microphone and speech recognition access.") }
        if !microphoneAvailable { result.append("Choose an available microphone.") }
        return result
    }
}
public enum RecoveryAction: Sendable {
    case permission(PermissionKind), voiceSettings, providerSettings, privacySettings
    public var title: String {
        switch self { case .permission(let kind): "Open \(kind.title) Settings"; case .voiceSettings: "Choose voice settings"; case .providerSettings: "Open Intelligence"; case .privacySettings: "Review privacy settings" }
    }
}
public enum VoiceCheckState: Equatable, Sendable { case idle, checking, passed, failed(String) }
public enum CapturePurpose: Sendable { case command, voiceCheck }

public enum SpotifyConnectionState: Equatable, Sendable {
    case unchecked, checking, connected(String), failed(String)
}
