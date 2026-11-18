import Foundation
import SottoTools

public enum SottoSettingKey: String, CaseIterable, Sendable {
    case appearance
    case notifications
    case audio_feedback
    case press_to_toggle
    case prepare_while_speaking
    case on_device_speech
    case history
    case automatic_intelligence
}

public protocol SottoSettingsBridge: Sendable {
    func apply(setting: SottoSettingKey, action: String, value: String) async throws -> ToolResult
}

struct SottoSettingsTool: Tool {
    private let bridge: (any SottoSettingsBridge)?
    init(bridge: (any SottoSettingsBridge)?) {
        self.bridge = bridge
    }

    let descriptor = ToolDescriptor(
        id: "sotto_settings",
        description: "Inspect or update Sotto's own app settings (appearance: system/light/dark, notifications, audio_feedback, press_to_toggle, prepare_while_speaking, on_device_speech, history, automatic_intelligence). Use system_settings or system_settings_ui for macOS system settings.",
        properties: [
            "setting": textProperty("Sotto setting to inspect or change", choices: SottoSettingKey.allCases.map(\.rawValue)),
            "action": textProperty("Action to perform", choices: ["on", "off", "toggle", "set", "status"]),
            "value": textProperty("Optional value (such as system, light, or dark for appearance)")
        ],
        required: ["setting", "action"],
        risk: .reversible,
        capabilities: [.settings]
    )

    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        try Task.checkCancellation()
        guard let rawSetting = arguments.object?["setting"]?.string,
              let setting = SottoSettingKey(rawValue: rawSetting),
              let action = arguments.object?["action"]?.string else {
            throw ToolError.invalid("Specify a valid Sotto setting and action.")
        }
        let value = arguments.object?["value"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let bridge else {
            throw ToolError.unavailable("Sotto preferences are unavailable outside the running app.")
        }
        return try await bridge.apply(setting: setting, action: action, value: value)
    }
}
