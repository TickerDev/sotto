import Foundation
import SottoTools

enum WorkflowActionKind: String, CaseIterable, Identifiable {
    case folder, application, openFile, revealFile, volume, audioOutput, timer, context, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .folder: "Open folder"
        case .application: "Open application"
        case .openFile: "Open file"
        case .revealFile: "Show file in Finder"
        case .volume: "Adjust volume"
        case .audioOutput: "Choose audio output"
        case .timer: "Start timer"
        case .context: "Check current application"
        case .settings: "Open System Settings"
        }
    }
}
struct WorkflowEditorStep: Identifiable {
    let id = UUID()
    var kind: WorkflowActionKind = .folder
    var path = ""
    var bundleID = ""
    var volume = 30.0
    var volumeAction = "set"
    var volumeValue = ""
    var outputID = 0.0
    var outputAction = "select"
    var seconds = 1500.0
    var timerName = ""
    var pane = "System Settings"
    init(kind: WorkflowActionKind = .folder) { self.kind = kind }
    init(_ step: JSONValue) throws {
        guard let object = step.object, Set(object.keys) == ["tool", "arguments"], let args = object["arguments"]?.object else { throw WorkflowEditorError.unsupported }
        switch object["tool"]?.string {
        case "open_folder": kind = .folder; path = args["path"]?.string ?? ""
        case "files.open": kind = .openFile; path = args["path"]?.string ?? ""
        case "files.reveal": kind = .revealFile; path = args["path"]?.string ?? ""
        case "apps.open": kind = .application; bundleID = args["bundle_id"]?.string ?? ""
        case "audio.volume":
            kind = .volume; volumeAction = args["action"]?.string ?? "set"
            volumeValue = args["value"]?.string ?? ""; volume = Double(volumeValue) ?? 30
            if !volumeValue.isEmpty && ["on", "open", "toggle"].contains(volumeAction) { volumeAction = "set" }
        case "audio.output":
            kind = .audioOutput; outputAction = args["action"]?.string ?? "select"
            if case .number(let value) = args["device_id"] { outputID = value }
        case "timers.start":
            kind = .timer; timerName = args["name"]?.string ?? ""
            if case .number(let value) = args["seconds"] { seconds = value }
        case "screen.context": kind = .context
        case "system.openSettings": kind = .settings; pane = args["value"]?.string ?? "System Settings"
        default: throw WorkflowEditorError.unsupported
        }
        if kind == .volume, (!volume.isFinite || !(0...100).contains(volume)) { throw WorkflowEditorError.unsupported }
        // Fail rather than silently discarding new/unknown fields when editing.
        let known: Set<String> = kind == .volume ? ["action", "value"] : kind == .settings ? ["value"] : Set(json.object?["arguments"]?.object?.keys.map { $0 } ?? [])
        guard Set(args.keys).isSubset(of: known) else { throw WorkflowEditorError.unsupported }
    }
    var json: JSONValue {
        let tool: String
        let args: [String: JSONValue]
        switch kind {
        case .folder: tool = "open_folder"; args = ["path": .string(path)]
        case .openFile: tool = "files.open"; args = ["path": .string(path)]
        case .revealFile: tool = "files.reveal"; args = ["path": .string(path)]
        case .application: tool = "apps.open"; args = ["bundle_id": .string(bundleID)]
        case .volume:
            tool = "audio.volume"
            var values = ["action": JSONValue.string(volumeAction)]
            if volumeAction == "set" { values["value"] = .string(volume.rounded() == volume ? String(Int(volume)) : String(volume)) }
            else if !volumeValue.isEmpty { values["value"] = .string(volumeValue) }
            args = values
        case .audioOutput: tool = "audio.output"; args = ["action": .string(outputAction), "device_id": .number(outputID)]
        case .timer: tool = "timers.start"; args = ["seconds": .number(seconds), "name": .string(timerName)]
        case .context: tool = "screen.context"; args = [:]
        case .settings: tool = "system.openSettings"; args = ["value": .string(pane)]
        }
        return .object(["tool": .string(tool), "arguments": .object(args)])
    }
}
enum WorkflowEditorError: LocalizedError {
    case unsupported
    var errorDescription: String? { "This workflow contains an action this editor cannot preserve exactly. It was not changed." }
}
