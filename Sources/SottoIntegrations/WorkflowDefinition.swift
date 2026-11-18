import Foundation
import SottoTools

/// Shared validation for voice creation, the native editor and execution preflight.
public enum WorkflowDefinition {
    public static let allowed: Set<String> = ["open_folder", "apps.open", "files.open", "files.reveal", "audio.volume", "audio.output", "timers.start", "screen.context", "system.openSettings"]
    public static var stepsSchema: JSONValue {
        .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(10),
            "items": .object(["type": .string("object"), "properties": .object([
                "tool": textProperty("Native action", choices: Array(allowed).sorted()),
                "arguments": .object(["type": .string("object"), "additionalProperties": .bool(true)])
            ]), "required": .array([.string("tool"), .string("arguments")]), "additionalProperties": .bool(false)])])
    }
    public static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func validateName(_ name: String) throws {
        guard !normalizedName(name).isEmpty, name.count <= 80,
              name.rangeOfCharacter(from: .controlCharacters) == nil else { throw ToolError.invalid("Choose a workflow name of 1–80 characters without line breaks") }
    }
    public static func validate(_ value: JSONValue, registry: ToolRegistry) throws -> [(any Tool, JSONValue)] {
        guard case .array(let steps) = value, (1...10).contains(steps.count) else { throw ToolError.invalid("A workflow needs 1 to 10 actions") }
        return try steps.enumerated().map { index, step in
            guard let object = step.object, Set(object.keys) == ["tool", "arguments"],
                  let id = object["tool"]?.string, allowed.contains(id), let arguments = object["arguments"] else { throw ToolError.denied("Step \(index + 1) is not a supported workflow action") }
            let tool = try registry.tool(id)
            try tool.descriptor.validate(arguments)
            try validateValues(id: id, arguments: arguments)
            return (tool, arguments)
        }
    }
    private static func validateValues(id: String, arguments: JSONValue) throws {
        let args = arguments.object ?? [:]
        switch id {
        case "open_folder", "files.open", "files.reveal":
            let path = args["path"]?.string ?? ""
            guard !path.contains("\0"), path.hasPrefix("/") || path.hasPrefix("~/") else { throw ToolError.invalid("Choose a local file or folder") }
        case "apps.open":
            let id = args["bundle_id"]?.string ?? ""
            guard !id.isEmpty, id.count <= 255, id.contains("."), !id.contains(where: \.isWhitespace) else { throw ToolError.invalid("Choose an installed application") }
        case "timers.start":
            guard case .number(let seconds) = args["seconds"], seconds.isFinite, (1...2_592_000).contains(seconds) else { throw ToolError.invalid("A timer must be between one second and 30 days") }
        case "audio.volume":
            let action = args["action"]?.string ?? ""
            let value = args["value"]?.string ?? ""
            if action == "set" || !value.isEmpty {
                guard let percent = Double(value), percent.isFinite, (0...100).contains(percent) else { throw ToolError.invalid("Volume must be between 0 and 100 percent") }
            }
        case "audio.output":
            guard case .number(let id) = args["device_id"], id.isFinite, id.rounded() == id, (0...Double(UInt32.max)).contains(id), args["action"]?.string != "select" || id > 0 else { throw ToolError.invalid("Choose a current audio output") }
        case "system.openSettings":
            guard SystemSettingsPaneCatalog.resolve(args["value"]?.string ?? "System Settings") != nil else { throw ToolError.invalid("Choose a supported System Settings page") }
        default: break
        }
    }
}
