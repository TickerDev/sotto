import Foundation

/// Human-readable review shared by the editor, saved list and immutable approval.
public struct WorkflowActionSummary: Sendable {
    public let title: String
    public let detail: String
    public init(_ step: JSONValue) {
        let object = step.object ?? [:], args = object["arguments"]?.object ?? [:]
        let path = args["path"]?.string ?? ""
        switch object["tool"]?.string {
        case "open_folder": title = "Open folder"; detail = path
        case "files.open": title = "Open file"; detail = path
        case "files.reveal": title = "Show in Finder"; detail = path
        case "apps.open":
            title = "Open application"
            let id = args["bundle_id"]?.string ?? ""
            detail = id.split(separator: ".").last.map(String.init) ?? id
        case "audio.volume":
            title = "Adjust volume"
            if args["action"]?.string == "set" { detail = (args["value"]?.string ?? "") + "%" }
            else { detail = (args["action"]?.string ?? "status").capitalized }
        case "audio.output":
            title = "Audio output"
            if args["action"]?.string == "list" { detail = "List available speakers" }
            else { detail = "Select device " + (args["device_id"]?.encoded ?? "") }
        case "timers.start":
            title = "Start timer"
            var duration = ""
            if case .number(let seconds) = args["seconds"], seconds.isFinite {
                if seconds >= 60 && seconds.truncatingRemainder(dividingBy: 60) == 0 { duration = (seconds / 60).formatted(.number.precision(.fractionLength(0...2))) + " minutes" }
                else { duration = seconds.formatted(.number.precision(.fractionLength(0...2))) + " seconds" }
            }
            let name = args["name"]?.string ?? ""
            detail = duration + (name.isEmpty ? "" : " · " + name)
        case "screen.context": title = "Check current application"; detail = "Read the foreground app name"
        case "system.openSettings": title = "Open System Settings"; detail = args["value"]?.string ?? "System Settings"
        default: title = "Unsupported action"; detail = "Review this workflow before running it"
        }
    }
}
