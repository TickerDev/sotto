import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import CoreWLAN
import Foundation
import ObjectiveC
import SottoTools

public enum SystemSettingKind: String, CaseIterable, Sendable {
    case night_shift
    case true_tone
    case dark_mode
    case wifi
    case bluetooth
    case volume
    case mute
    case brightness
    case dock_autohide
    case dock_magnification
    case dock_position
    case show_hidden_files
    case show_file_extensions
    case open_pane
    case not_listed
}

public enum SystemPowerAction: String, CaseIterable, Sendable {
    case sleep_display
    case screen_saver
    case lock_screen
}

public enum SystemSettingAction: String, CaseIterable, Sendable {
    case on, off, toggle, status, set, up, down, open
}

public enum SystemSettingsPaneCatalog {
    public struct PaneMatch: Sendable, Equatable {
        public let title: String
        public let url: URL
    }

    public static func resolve(_ raw: String, controlHint: String = "") -> PaneMatch? {
        let normalized = normalize(raw)
        let hint = normalize(controlHint)

        // Subpane specialization for Accessibility controls so deep-links land directly on the toggles.
        if normalized == "accessibility" || normalized.contains("accessibility") {
            if hint.contains("motion") || hint.contains("animated") || hint.contains("blinking cursor") {
                return PaneMatch(title: "Accessibility · Motion", url: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Motion")!)
            }
            if hint.contains("contrast") || hint.contains("transparency") || hint.contains("invert") || hint.contains("color") || hint.contains("border") || hint.contains("flashing") || hint.contains("pointer") || hint.contains("horizontal text") {
                return PaneMatch(title: "Accessibility · Display", url: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display")!)
            }
            if hint.contains("voiceover") {
                return PaneMatch(title: "Accessibility · VoiceOver", url: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?VoiceOver")!)
            }
            if hint.contains("zoom") {
                return PaneMatch(title: "Accessibility · Zoom", url: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Zoom")!)
            }
            if hint.contains("caption") || hint.contains("subtitle") {
                return PaneMatch(title: "Accessibility · Captions", url: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Captioning")!)
            }
        }

        let entries: [(keys: [String], title: String, target: String)] = [
            (["reduce motion", "auto play animated", "motion cues"], "Accessibility · Motion", "com.apple.Accessibility-Settings.extension?Motion"),
            (["increase contrast", "reduce transparency", "invert colors", "color filters", "differentiate without color", "accessibility display"], "Accessibility · Display", "com.apple.Accessibility-Settings.extension?Display"),
            (["voiceover"], "Accessibility · VoiceOver", "com.apple.Accessibility-Settings.extension?VoiceOver"),
            (["accessibility"], "Accessibility", "com.apple.Accessibility-Settings.extension"),
            (["night shift", "true tone", "display", "displays", "resolution", "brightness"], "Displays", "com.apple.Displays-Settings.extension"),
            (["sound", "audio", "volume", "speaker", "microphone input", "output"], "Sound", "com.apple.Sound-Settings.extension"),
            (["wifi", "wi fi"], "Wi-Fi", "com.apple.wifi-settings-extension"),
            (["bluetooth"], "Bluetooth", "com.apple.BluetoothSettings"),
            (["network", "ethernet"], "Network", "com.apple.Network-Settings.extension"),
            (["vpn"], "VPN", "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"),
            (["battery", "low power", "battery saver", "battery saving", "power saver", "power saving", "energy saver", "power", "energy"], "Battery", "com.apple.Battery-Settings.extension"),
            (["appearance", "dark mode", "light mode", "accent color"], "Appearance", "com.apple.Appearance-Settings.extension"),
            (["desktop", "dock", "stage manager", "mission control", "hot corners"], "Desktop & Dock", "com.apple.Desktop-Settings.extension"),
            (["menu bar", "control center"], "Menu Bar", "com.apple.ControlCenter-Settings.extension"),
            (["siri", "apple intelligence"], "Apple Intelligence & Siri", "com.apple.Siri-Settings.extension"),
            (["spotlight", "search"], "Spotlight", "com.apple.Spotlight-Settings.extension"),
            (["wallpaper"], "Wallpaper", "com.apple.Wallpaper-Settings.extension"),
            (["notifications", "notification"], "Notifications", "com.apple.Notifications-Settings.extension"),
            (["focus", "do not disturb"], "Focus", "com.apple.Focus-Settings.extension"),
            (["screen time"], "Screen Time", "com.apple.Screen-Time-Settings.extension"),
            (["lock screen", "screen saver"], "Lock Screen", "com.apple.Lock-Screen-Settings.extension"),
            (["automation"], "Privacy & Security · Automation", "com.apple.preference.security?Privacy_Automation"),
            (["microphone"], "Privacy & Security · Microphone", "com.apple.preference.security?Privacy_Microphone"),
            (["camera"], "Privacy & Security · Camera", "com.apple.preference.security?Privacy_Camera"),
            (["privacy", "security"], "Privacy & Security", "com.apple.preference.security"),
            (["touch id", "password"], "Touch ID & Password", "com.apple.Touch-ID-Settings.extension"),
            (["users", "groups", "accounts"], "Users & Groups", "com.apple.Users-Groups-Settings.extension"),
            (["icloud", "apple id", "apple account"], "Apple Account", "com.apple.AppleIDSettings"),
            (["internet accounts"], "Internet Accounts", "com.apple.Internet-Accounts-Settings.extension"),
            (["wallet", "apple pay"], "Wallet & Apple Pay", "com.apple.WalletSettingsExtension"),
            (["keyboard"], "Keyboard", "com.apple.Keyboard-Settings.extension"),
            (["trackpad"], "Trackpad", "com.apple.Trackpad-Settings.extension"),
            (["mouse"], "Mouse", "com.apple.Mouse-Settings.extension"),
            (["printers", "scanners", "printer"], "Printers & Scanners", "com.apple.Print-Scan-Settings.extension"),
            (["airdrop", "handoff"], "AirDrop & Handoff", "com.apple.AirDrop-Handoff-Settings.extension"),
            (["software update", "update", "macos update"], "Software Update", "com.apple.Software-Update-Settings.extension"),
            (["time machine", "backup"], "Time Machine", "com.apple.Time-Machine-Settings.extension"),
            (["sharing"], "Sharing", "com.apple.Sharing-Settings.extension"),
            (["login items", "extensions"], "Login Items & Extensions", "com.apple.LoginItems-Settings.extension"),
            (["date", "time"], "Date & Time", "com.apple.Date-Time-Settings.extension"),
            (["language", "region"], "Language & Region", "com.apple.Localization-Settings.extension"),
            (["startup disk"], "Startup Disk", "com.apple.Startup-Disk-Settings.extension"),
            (["general", "about", "storage"], "General", "com.apple.GeneralSettings"),
        ]

        let combined = [normalized, hint].filter { !$0.isEmpty }.joined(separator: " ")
        for entry in entries {
            if entry.keys.contains(where: { normalized == $0 || normalized.contains($0) || (!combined.isEmpty && combined.contains($0)) }) {
                if let url = URL(string: "x-apple.systempreferences:\(entry.target)") {
                    return PaneMatch(title: entry.title, url: url)
                }
            }
        }
        if raw.contains(".") && raw.contains("com.apple.") {
            if let url = URL(string: "x-apple.systempreferences:\(raw.trimmingCharacters(in: .whitespacesAndNewlines))") {
                return PaneMatch(title: raw, url: url)
            }
        }
        if normalized == "system settings" || normalized == "settings" || normalized == "preferences" {
            return PaneMatch(title: "System Settings", url: URL(string: "x-apple.systempreferences:")!)
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "&", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

struct SystemSettingsTool: Tool {
    let descriptor = ToolDescriptor(
        id: "system_settings",
        description: "Inspect or change specific direct macOS settings: night_shift, true_tone, dark_mode, wifi, bluetooth, volume (audio/sound output level), mute, brightness, dock_autohide, dock_magnification, dock_position, show_hidden_files, show_file_extensions, or open_pane. For Battery/Low Power Mode, battery saver, Reduce Motion, Do Not Disturb, or any other System Settings control, use system_settings_ui instead. Pick 'not_listed' if the requested setting is not explicitly in this list—never substitute wifi or another unrelated setting.",
        properties: [
            "setting": textProperty("Exact setting to inspect or change, or 'not_listed' if the requested setting is not explicitly listed here.", choices: SystemSettingKind.allCases.map(\.rawValue)),
            "action": textProperty("Action to perform (use 'set' when setting volume, brightness, or night_shift warmth to a percentage)", choices: SystemSettingAction.allCases.map(\.rawValue)),
            "value": textProperty("Optional value: 0-100 percentage with action 'set' for volume, brightness, or night_shift warmth; left/bottom/right for dock_position; or pane name for open_pane.")
        ],
        required: ["setting", "action"],
        risk: .reversible,
        capabilities: [.settings]
    )

    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        try Task.checkCancellation()
        guard let rawSetting = arguments.object?["setting"]?.string,
              let setting = SystemSettingKind(rawValue: rawSetting),
              let rawAction = arguments.object?["action"]?.string,
              let action = SystemSettingAction(rawValue: rawAction) else {
            throw ToolError.invalid("Specify a valid setting and action.")
        }
        let value = arguments.object?["value"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch setting {
        case .night_shift:
            return try NightShiftController.run(action: action, value: value)
        case .true_tone:
            return try TrueToneController.run(action: action)
        case .brightness:
            return try BrightnessController.run(action: action, value: value)
        case .volume:
            return try AudioVolumeController.runVolume(action: action, value: value)
        case .mute:
            return try AudioVolumeController.runMute(action: action)
        case .wifi:
            return try await WiFiController.run(action: action)
        case .bluetooth:
            return try await BluetoothController.run(action: action)
        case .dark_mode:
            return try await SystemEventsSettingsController.runDarkMode(action: action)
        case .dock_autohide:
            return try await SystemEventsSettingsController.runDockAutohide(action: action)
        case .dock_magnification:
            return try await SystemEventsSettingsController.runDockMagnification(action: action)
        case .dock_position:
            return try await SystemEventsSettingsController.runDockPosition(action: action, value: value)
        case .show_hidden_files:
            return try await FinderSettingsController.runBool(key: "AppleShowAllFiles", label: "Hidden files", action: action)
        case .show_file_extensions:
            return try await FinderSettingsController.runBool(key: "AppleShowAllExtensions", label: "Filename extensions", action: action)
        case .open_pane:
            return try await MainActor.run {
                let target = value.isEmpty ? "System Settings" : value
                guard let match = SystemSettingsPaneCatalog.resolve(target) else {
                    if let fallback = URL(string: "x-apple.systempreferences:"), NSWorkspace.shared.open(fallback) {
                        return ToolResult("Opened System Settings")
                    }
                    throw ToolError.unavailable("Could not open System Settings.")
                }
                guard NSWorkspace.shared.open(match.url) else {
                    throw ToolError.unavailable("Could not open \(match.title) in System Settings.")
                }
                return ToolResult("Opened \(match.title) in System Settings")
            }
        case .not_listed:
            throw ToolError.invalid("That setting is not a direct system_settings toggle. Use system_settings_ui with the System Settings pane and control name, or tell the user if it is unavailable.")
        }
    }
}

struct SystemPowerTool: Tool {
    let descriptor = ToolDescriptor(
        id: "system_power",
        description: "Sleep the display, start the screen saver, or lock the Mac screen. Only use when the user explicitly asks to lock the screen, sleep the display, or start the screen saver (never for battery saver or power saving mode).",
        properties: [
            "action": textProperty("Power or session action to perform", choices: SystemPowerAction.allCases.map(\.rawValue))
        ],
        required: ["action"],
        risk: .consequential,
        capabilities: [.settings]
    )

    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        try Task.checkCancellation()
        guard let rawAction = arguments.object?["action"]?.string,
              let action = SystemPowerAction(rawValue: rawAction) else {
            throw ToolError.invalid("Specify a valid power or session action.")
        }
        switch action {
        case .sleep_display:
            return try await PowerSessionController.sleepDisplay()
        case .screen_saver:
            return try await PowerSessionController.startScreenSaver()
        case .lock_screen:
            return try PowerSessionController.lockScreen()
        }
    }
}

// MARK: - CoreBrightness (Night Shift & True Tone)

private struct DynamicLibrary: @unchecked Sendable {
    let rawValue: UnsafeMutableRawPointer?

    init(_ path: String) {
        self.rawValue = dlopen(path, RTLD_NOW)
    }

    func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let rawValue else { return nil }
        return dlsym(rawValue, name)
    }
}

private enum CoreBrightnessLoader {
    static let library = DynamicLibrary("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness")
}

private enum NightShiftController {
    private struct BlueLightStatusData {
        var active: ObjCBool = false
        var enabled: ObjCBool = false
        var sunSchedulePermitted: ObjCBool = false
        var mode: Int32 = 0
        var schedule: (Int32, Int32, Int32, Int32) = (0, 0, 0, 0)
        var disableFlags: UInt64 = 0
        var available: ObjCBool = false
    }

    static func run(action: SystemSettingAction, value: String) throws -> ToolResult {
        _ = CoreBrightnessLoader.library.rawValue
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            throw ToolError.unavailable("Night Shift control is unavailable on this macOS version.")
        }
        let supportsSel = NSSelectorFromString("supportsBlueLightReduction")
        if cls.responds(to: supportsSel) {
            let imp = cls.method(for: supportsSel)
            typealias SupportsFn = @convention(c) (AnyClass, Selector) -> ObjCBool
            let fn = unsafeBitCast(imp, to: SupportsFn.self)
            if !fn(cls, supportsSel).boolValue {
                throw ToolError.unavailable("Night Shift is not supported on this display.")
            }
        }

        let client = cls.init()
        var current = try readStatus(client: client)
        guard current.available.boolValue else {
            throw ToolError.unavailable("Night Shift is currently unavailable on this display.")
        }

        if action == .status {
            let strength = readStrength(client: client)
            let state = current.enabled.boolValue ? "on" : "off"
            let warmth = strength.map { " (warmth \(Int(round($0 * 100)))%)" } ?? ""
            return ToolResult("Night Shift is \(state)\(warmth)", data: .object([
                "enabled": .bool(current.enabled.boolValue),
                "strength": strength.map { .number(Double(Int(round($0 * 100)))) } ?? .null
            ]))
        }

        var warmthApplied: Int?
        if action == .set {
            let pct = try parsePercentage(value, defaultMessage: "Specify a Night Shift warmth percentage from 0 to 100.")
            if !current.enabled.boolValue {
                try setEnabled(client: client, enabled: true)
            }
            try setStrength(client: client, strength: Float(pct) / 100.0)
            warmthApplied = pct
        } else {
            let target: Bool
            switch action {
            case .on, .open: target = true
            case .off: target = false
            case .toggle: target = !current.enabled.boolValue
            default: throw ToolError.invalid("Use on, off, toggle, set, or status for Night Shift.")
            }
            try setEnabled(client: client, enabled: target)
            if target, !value.isEmpty {
                let pct = try parsePercentage(value, defaultMessage: "Specify a Night Shift warmth percentage from 0 to 100.")
                try setStrength(client: client, strength: Float(pct) / 100.0)
                warmthApplied = pct
            }
        }

        current = try readStatus(client: client)
        let isOn = current.enabled.boolValue
        let summary: String
        if let warmthApplied {
            summary = "Night Shift is \(isOn ? "on" : "off") with warmth at \(warmthApplied)%"
        } else {
            summary = isOn ? "Turned Night Shift on" : "Turned Night Shift off"
        }
        return ToolResult(summary, data: .object(["enabled": .bool(isOn)]))
    }

    private static func readStatus(client: NSObject) throws -> BlueLightStatusData {
        var status = BlueLightStatusData()
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: sel) else { throw ToolError.unavailable("Cannot read Night Shift status.") }
        let imp = client.method(for: sel)
        typealias GetStatusFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> ObjCBool
        let fn = unsafeBitCast(imp, to: GetStatusFn.self)
        let ok = withUnsafeMutablePointer(to: &status) { ptr in fn(client, sel, UnsafeMutableRawPointer(ptr)) }
        guard ok.boolValue else { throw ToolError.unavailable("Could not read Night Shift status.") }
        return status
    }

    private static func setEnabled(client: NSObject, enabled: Bool) throws {
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel) else { throw ToolError.unavailable("Cannot change Night Shift state.") }
        let imp = client.method(for: sel)
        typealias SetEnabledFn = @convention(c) (AnyObject, Selector, ObjCBool) -> ObjCBool
        let fn = unsafeBitCast(imp, to: SetEnabledFn.self)
        guard fn(client, sel, ObjCBool(enabled)).boolValue else {
            throw ToolError.unavailable("macOS could not update Night Shift.")
        }
    }

    private static func readStrength(client: NSObject) -> Float? {
        let sel = NSSelectorFromString("getStrength:")
        guard client.responds(to: sel) else { return nil }
        var strength: Float = 0
        let imp = client.method(for: sel)
        typealias GetStrengthFn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> ObjCBool
        let fn = unsafeBitCast(imp, to: GetStrengthFn.self)
        return fn(client, sel, &strength).boolValue ? strength : nil
    }

    private static func setStrength(client: NSObject, strength: Float) throws {
        let sel = NSSelectorFromString("setStrength:commit:")
        guard client.responds(to: sel) else { throw ToolError.unavailable("Cannot adjust Night Shift warmth.") }
        let imp = client.method(for: sel)
        typealias SetStrengthFn = @convention(c) (AnyObject, Selector, Float, ObjCBool) -> ObjCBool
        let fn = unsafeBitCast(imp, to: SetStrengthFn.self)
        guard fn(client, sel, max(0, min(1, strength)), ObjCBool(true)).boolValue else {
            throw ToolError.unavailable("macOS could not update Night Shift warmth.")
        }
    }
}

private enum TrueToneController {
    static func run(action: SystemSettingAction) throws -> ToolResult {
        _ = CoreBrightnessLoader.library.rawValue
        guard let cls = NSClassFromString("CBTrueToneClient") as? NSObject.Type else {
            throw ToolError.unavailable("True Tone control is unavailable on this macOS version.")
        }
        let client = cls.init()
        let supported = (client.value(forKey: "supported") as? Bool) ?? false
        let available = (client.value(forKey: "available") as? Bool) ?? false
        guard supported, available else {
            throw ToolError.unavailable("True Tone is not supported on this display.")
        }
        let enabled = (client.value(forKey: "enabled") as? Bool) ?? false
        if action == .status {
            return ToolResult("True Tone is \(enabled ? "on" : "off")", data: .object(["enabled": .bool(enabled)]))
        }
        let target: Bool
        switch action {
        case .on, .open: target = true
        case .off: target = false
        case .toggle: target = !enabled
        default: throw ToolError.invalid("Use on, off, toggle, or status for True Tone.")
        }
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel) else { throw ToolError.unavailable("Cannot change True Tone.") }
        let imp = client.method(for: sel)
        typealias SetFn = @convention(c) (AnyObject, Selector, ObjCBool) -> ObjCBool
        let fn = unsafeBitCast(imp, to: SetFn.self)
        guard fn(client, sel, ObjCBool(target)).boolValue else {
            throw ToolError.unavailable("macOS could not update True Tone.")
        }
        let updated = (client.value(forKey: "enabled") as? Bool) ?? target
        return ToolResult(updated ? "Turned True Tone on" : "Turned True Tone off", data: .object(["enabled": .bool(updated)]))
    }
}

// MARK: - Display Brightness

private enum BrightnessController {
    private static let library = DynamicLibrary("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")

    static func run(action: SystemSettingAction, value: String) throws -> ToolResult {
        guard let getSym = library.symbol("DisplayServicesGetBrightness"),
              let setSym = library.symbol("DisplayServicesSetBrightness") else {
            throw ToolError.unavailable("Display brightness control is unavailable on this Mac.")
        }
        typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let getBrightness = unsafeBitCast(getSym, to: GetFn.self)
        let setBrightness = unsafeBitCast(setSym, to: SetFn.self)

        let display = CGMainDisplayID()
        var current: Float = 0
        guard getBrightness(display, &current) == 0 else {
            throw ToolError.unavailable("Brightness adjustment is not supported on the main display.")
        }
        let currentPct = Int(round(current * 100))
        if action == .status {
            return ToolResult("Display brightness is \(currentPct)%", data: .object(["brightness": .number(Double(currentPct))]))
        }

        let target: Float
        switch action {
        case .set:
            let pct = try parsePercentage(value, defaultMessage: "Specify a brightness percentage from 0 to 100.")
            target = Float(pct) / 100.0
        case .on where !value.isEmpty, .open where !value.isEmpty, .toggle where !value.isEmpty:
            let pct = try parsePercentage(value, defaultMessage: "Specify a brightness percentage from 0 to 100.")
            target = Float(pct) / 100.0
        case .up:
            let step = value.isEmpty ? 12 : (try? parsePercentage(value, defaultMessage: "")) ?? 12
            target = min(1.0, current + Float(step) / 100.0)
        case .down:
            let step = value.isEmpty ? 12 : (try? parsePercentage(value, defaultMessage: "")) ?? 12
            target = max(0.0, current - Float(step) / 100.0)
        default:
            throw ToolError.invalid("Use set, up, down, or status for brightness.")
        }

        guard setBrightness(display, target) == 0 else {
            throw ToolError.unavailable("macOS could not adjust display brightness.")
        }
        var updated: Float = target
        _ = getBrightness(display, &updated)
        let updatedPct = Int(round(updated * 100))
        return ToolResult("Display brightness set to \(updatedPct)%", data: .object(["brightness": .number(Double(updatedPct))]))
    }
}

// MARK: - CoreAudio Volume & Mute

private enum AudioVolumeController {
    static func runVolume(action: SystemSettingAction, value: String) throws -> ToolResult {
        let device = try defaultOutputDevice()
        let current = try getVolume(device: device)
        let currentPct = Int(round(current * 100))
        let muted = getMute(device: device) ?? false

        if action == .status {
            let muteText = muted ? " (muted)" : ""
            return ToolResult("Output volume is \(currentPct)%\(muteText)", data: .object(["volume": .number(Double(currentPct)), "muted": .bool(muted)]))
        }

        let target: Float32
        switch action {
        case .set:
            let pct = try parsePercentage(value, defaultMessage: "Specify a volume percentage from 0 to 100.")
            target = Float32(pct) / 100.0
        case .on where !value.isEmpty, .open where !value.isEmpty, .toggle where !value.isEmpty:
            let pct = try parsePercentage(value, defaultMessage: "Specify a volume percentage from 0 to 100.")
            target = Float32(pct) / 100.0
        case .up:
            let step = value.isEmpty ? 10 : (try? parsePercentage(value, defaultMessage: "")) ?? 10
            target = min(1.0, current + Float32(step) / 100.0)
        case .down:
            let step = value.isEmpty ? 10 : (try? parsePercentage(value, defaultMessage: "")) ?? 10
            target = max(0.0, current - Float32(step) / 100.0)
        case .off:
            try setMute(device: device, muted: true)
            return ToolResult("Muted output volume")
        case .on:
            try setMute(device: device, muted: false)
            return ToolResult("Unmuted output volume (\(currentPct)%)")
        default:
            throw ToolError.invalid("Use set, up, down, or status for volume.")
        }

        try setVolume(device: device, volume: target)
        if target > 0, muted {
            try? setMute(device: device, muted: false)
        }
        let updatedVolume = (try? getVolume(device: device)) ?? target
        let updatedPct = Int(round(updatedVolume * 100))
        return ToolResult("Volume set to \(updatedPct)%", data: .object(["volume": .number(Double(updatedPct))]))
    }

    static func runMute(action: SystemSettingAction) throws -> ToolResult {
        let device = try defaultOutputDevice()
        let current = getMute(device: device) ?? false
        if action == .status {
            return ToolResult(current ? "Audio output is muted" : "Audio output is not muted", data: .object(["muted": .bool(current)]))
        }
        let target: Bool
        switch action {
        case .on, .open: target = true
        case .off: target = false
        case .toggle: target = !current
        default: throw ToolError.invalid("Use on, off, toggle, or status for mute.")
        }
        try setMute(device: device, muted: target)
        let updated = getMute(device: device) ?? target
        return ToolResult(updated ? "Muted audio output" : "Unmuted audio output", data: .object(["muted": .bool(updated)]))
    }

    private static func defaultOutputDevice() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw ToolError.unavailable("No default audio output device is available.")
        }
        return deviceID
    }

    private static func getVolume(device: AudioDeviceID) throws -> Float32 {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else {
            throw ToolError.unavailable("Volume control is not supported for the current output device.")
        }
        return volume
    }

    private static func setVolume(device: AudioDeviceID, volume: Float32) throws {
        var clamped = max(0, min(1, volume))
        var settable = DarwinBoolean(false)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else {
            throw ToolError.unavailable("The current audio output device does not allow volume changes.")
        }
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &clamped)
        guard status == noErr else {
            throw ToolError.unavailable("macOS could not update output volume.")
        }
    }

    private static func getMute(device: AudioDeviceID) -> Bool? {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    private static func setMute(device: AudioDeviceID, muted: Bool) throws {
        var value: UInt32 = muted ? 1 : 0
        var settable = DarwinBoolean(false)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else {
            throw ToolError.unavailable("The current audio output device does not allow muting.")
        }
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            throw ToolError.unavailable("macOS could not update mute state.")
        }
    }
}

// MARK: - Wi-Fi & Bluetooth

private enum WiFiController {
    static func run(action: SystemSettingAction) async throws -> ToolResult {
        guard let interface = CWWiFiClient.shared().interface() else {
            throw ToolError.unavailable("No Wi-Fi interface was found on this Mac.")
        }
        let current = interface.powerOn()
        if action == .status {
            return ToolResult("Wi-Fi is \(current ? "on" : "off")", data: .object(["enabled": .bool(current)]))
        }
        let target: Bool
        switch action {
        case .on, .open: target = true
        case .off: target = false
        case .toggle: target = !current
        default: throw ToolError.invalid("Use on, off, toggle, or status for Wi-Fi.")
        }
        try interface.setPower(target)
        for _ in 0..<10 {
            try Task.checkCancellation()
            if interface.powerOn() == target { break }
            try await Task.sleep(for: .milliseconds(80))
        }
        let updated = interface.powerOn()
        return ToolResult(updated ? "Turned Wi-Fi on" : "Turned Wi-Fi off", data: .object(["enabled": .bool(updated)]))
    }
}

private enum BluetoothController {
    private static let library = DynamicLibrary("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth")

    static func run(action: SystemSettingAction) async throws -> ToolResult {
        guard let getSym = library.symbol("IOBluetoothPreferenceGetControllerPowerState"),
              let setSym = library.symbol("IOBluetoothPreferenceSetControllerPowerState") else {
            throw ToolError.unavailable("Bluetooth control is unavailable on this Mac.")
        }
        typealias GetFn = @convention(c) () -> Int32
        typealias SetFn = @convention(c) (Int32) -> Void
        let getState = unsafeBitCast(getSym, to: GetFn.self)
        let setState = unsafeBitCast(setSym, to: SetFn.self)

        let current = getState() != 0
        if action == .status {
            return ToolResult("Bluetooth is \(current ? "on" : "off")", data: .object(["enabled": .bool(current)]))
        }
        let target: Bool
        switch action {
        case .on, .open: target = true
        case .off: target = false
        case .toggle: target = !current
        default: throw ToolError.invalid("Use on, off, toggle, or status for Bluetooth.")
        }
        setState(target ? 1 : 0)
        for _ in 0..<12 {
            try Task.checkCancellation()
            if (getState() != 0) == target { break }
            try await Task.sleep(for: .milliseconds(80))
        }
        let updated = getState() != 0
        return ToolResult(updated ? "Turned Bluetooth on" : "Turned Bluetooth off", data: .object(["enabled": .bool(updated)]))
    }
}

// MARK: - System Events Automation (Dark Mode & Dock)

private enum SystemEventsSettingsController {
    static func runDarkMode(action: SystemSettingAction) async throws -> ToolResult {
        let script: String
        switch action {
        case .status:
            script = "tell application \"System Events\" to return dark mode of appearance preferences"
        case .on, .open:
            script = """
            tell application "System Events"
                set dark mode of appearance preferences to true
                return dark mode of appearance preferences
            end tell
            """
        case .off:
            script = """
            tell application "System Events"
                set dark mode of appearance preferences to false
                return dark mode of appearance preferences
            end tell
            """
        case .toggle:
            script = """
            tell application "System Events"
                set dark mode of appearance preferences to (not dark mode of appearance preferences)
                return dark mode of appearance preferences
            end tell
            """
        default:
            throw ToolError.invalid("Use on, off, toggle, or status for Dark Mode.")
        }
        let output = try await AppleScriptExecutor().execute(script, targetName: "System Events")
        let isDark = output.lowercased() == "true"
        if action == .status {
            return ToolResult("Appearance is \(isDark ? "Dark" : "Light")", data: .object(["dark_mode": .bool(isDark)]))
        }
        return ToolResult(isDark ? "Turned Dark Mode on" : "Turned Dark Mode off", data: .object(["dark_mode": .bool(isDark)]))
    }

    static func runDockAutohide(action: SystemSettingAction) async throws -> ToolResult {
        let script: String
        switch action {
        case .status:
            script = "tell application \"System Events\" to return autohide of dock preferences"
        case .on, .open:
            script = "tell application \"System Events\"\nset autohide of dock preferences to true\nreturn autohide of dock preferences\nend tell"
        case .off:
            script = "tell application \"System Events\"\nset autohide of dock preferences to false\nreturn autohide of dock preferences\nend tell"
        case .toggle:
            script = "tell application \"System Events\"\nset autohide of dock preferences to (not autohide of dock preferences)\nreturn autohide of dock preferences\nend tell"
        default:
            throw ToolError.invalid("Use on, off, toggle, or status for Dock auto-hide.")
        }
        let output = try await AppleScriptExecutor().execute(script, targetName: "System Events")
        let enabled = output.lowercased() == "true"
        if action == .status {
            return ToolResult("Dock auto-hide is \(enabled ? "on" : "off")", data: .object(["enabled": .bool(enabled)]))
        }
        return ToolResult(enabled ? "Turned Dock auto-hide on" : "Turned Dock auto-hide off", data: .object(["enabled": .bool(enabled)]))
    }

    static func runDockMagnification(action: SystemSettingAction) async throws -> ToolResult {
        let script: String
        switch action {
        case .status:
            script = "tell application \"System Events\" to return magnification of dock preferences"
        case .on, .open:
            script = "tell application \"System Events\"\nset magnification of dock preferences to true\nreturn magnification of dock preferences\nend tell"
        case .off:
            script = "tell application \"System Events\"\nset magnification of dock preferences to false\nreturn magnification of dock preferences\nend tell"
        case .toggle:
            script = "tell application \"System Events\"\nset magnification of dock preferences to (not magnification of dock preferences)\nreturn magnification of dock preferences\nend tell"
        default:
            throw ToolError.invalid("Use on, off, toggle, or status for Dock magnification.")
        }
        let output = try await AppleScriptExecutor().execute(script, targetName: "System Events")
        let enabled = output.lowercased() == "true"
        if action == .status {
            return ToolResult("Dock magnification is \(enabled ? "on" : "off")", data: .object(["enabled": .bool(enabled)]))
        }
        return ToolResult(enabled ? "Turned Dock magnification on" : "Turned Dock magnification off", data: .object(["enabled": .bool(enabled)]))
    }

    static func runDockPosition(action: SystemSettingAction, value: String) async throws -> ToolResult {
        if action == .status {
            let output = try await AppleScriptExecutor().execute("tell application \"System Events\" to return screen edge of dock preferences as string", targetName: "System Events")
            return ToolResult("Dock position is \(output)", data: .object(["position": .string(output)]))
        }
        let edge = value.lowercased()
        guard ["left", "bottom", "right"].contains(edge) else {
            throw ToolError.invalid("Choose left, bottom, or right for Dock position.")
        }
        let script = "tell application \"System Events\"\nset screen edge of dock preferences to \(edge)\nreturn screen edge of dock preferences as string\nend tell"
        let output = try await AppleScriptExecutor().execute(script, targetName: "System Events")
        return ToolResult("Moved Dock to \(output)", data: .object(["position": .string(output)]))
    }
}

// MARK: - Finder & Power / Session

private enum FinderSettingsController {
    static func runBool(key: String, label: String, action: SystemSettingAction) async throws -> ToolResult {
        let suite = UserDefaults(suiteName: "com.apple.finder")
        let current = suite?.bool(forKey: key) ?? false
        if action == .status {
            return ToolResult("\(label) are currently \(current ? "shown" : "hidden")", data: .object(["enabled": .bool(current)]))
        }
        let target: Bool
        switch action {
        case .on, .open: target = true
        case .off: target = false
        case .toggle: target = !current
        default: throw ToolError.invalid("Use on, off, toggle, or status.")
        }
        try await ProcessRunner.run(executable: "/usr/bin/defaults", arguments: ["write", "com.apple.finder", key, "-bool", target ? "true" : "false"])
        _ = try? await ProcessRunner.run(executable: "/usr/bin/killall", arguments: ["Finder"])
        return ToolResult("\(target ? "Showing" : "Hiding") \(label.lowercased()) in Finder", data: .object(["enabled": .bool(target)]))
    }
}

private enum PowerSessionController {
    static func sleepDisplay() async throws -> ToolResult {
        try await ProcessRunner.run(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"])
        return ToolResult("Put display to sleep")
    }

    static func startScreenSaver() async throws -> ToolResult {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw ToolError.unavailable("Could not start Screen Saver.") }
        return ToolResult("Started Screen Saver")
    }

    static func lockScreen() throws -> ToolResult {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
              let sym = dlsym(handle, "SACLockScreenImmediate") else {
            throw ToolError.unavailable("Screen lock is unavailable on this Mac.")
        }
        typealias LockFn = @convention(c) () -> Int32
        let lockFn = unsafeBitCast(sym, to: LockFn.self)
        _ = lockFn()
        return ToolResult("Locked the screen")
    }
}

// MARK: - Helpers

private enum ProcessRunner {
    @discardableResult
    static func run(executable: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let process = Process()
            let out = Pipe()
            let err = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = out
            process.standardError = err
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let errorText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw ToolError.unavailable(errorText.isEmpty ? "Command exited with status \(process.terminationStatus)" : errorText)
            }
            return output
        }.value
    }
}

private func parsePercentage(_ raw: String, defaultMessage: String) throws -> Int {
    let cleaned = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let number = Double(cleaned), number.isFinite else {
        throw ToolError.invalid(defaultMessage.isEmpty ? "Provide a percentage from 0 to 100." : defaultMessage)
    }
    return max(0, min(100, Int(round(number))))
}
