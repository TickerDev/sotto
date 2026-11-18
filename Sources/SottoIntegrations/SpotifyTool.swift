import AppKit
import SottoTools

/// Model input chooses an enum; it is never interpolated into executable script text.
enum SpotifyAction: String, CaseIterable, Sendable {
    case play, pause, next, previous, current
    var script: String {
        let command: String
        switch self { case .play: command = "play"; case .pause: command = "pause"; case .next: command = "next track"; case .previous: command = "previous track"; case .current: command = "" }
        let verify: String
        switch self {
        case .play: verify = "if playbackState is \"playing\" then exit repeat"
        case .pause: verify = "if playbackState is \"paused\" or playbackState is \"stopped\" then exit repeat"
        default: verify = "exit repeat"
        }
        return """
        with timeout of 20 seconds
            tell application id "com.spotify.client"
                \(command)
                repeat 20 times
                    set playbackState to player state as string
                    \(verify)
                    delay 0.05
                end repeat
                set trackName to "No current track"
                try
                    set trackName to name of current track
                end try
                return playbackState & tab & trackName
            end tell
        end timeout
        """
    }
    func result(_ output: String) throws -> ToolResult {
        let parts = output.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, ["playing", "paused", "stopped"].contains(String(parts[0])) else { throw ToolError.unavailable("Spotify returned no valid playback state") }
        if self == .play && parts[0] != "playing" { throw ToolError.unavailable("Spotify did not confirm playback. Choose a playable track in Spotify first.") }
        if self == .pause && parts[0] == "playing" { throw ToolError.unavailable("Spotify did not confirm that playback stopped") }
        return ToolResult("\(String(parts[0]).capitalized) · \(parts[1])")
    }
}
struct SpotifyTool: Tool {
    let descriptor = ToolDescriptor(id: "spotify", description: "Control Spotify playback", properties: ["action": textProperty("Playback action", choices: SpotifyAction.allCases.map(\.rawValue))], required: ["action"], risk: .reversible, capabilities: [.automation])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        guard let raw = arguments.object?["action"]?.string, let action = SpotifyAction(rawValue: raw) else { throw ToolError.invalid("Invalid Spotify action") }
        try await MainActor.run {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil else { throw ToolError.unavailable("Spotify is not installed") }
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else { throw ToolError.unavailable("Open Spotify and start a track first") }
        }
        let output = try await AppleScriptExecutor().execute(action.script)
        return try action.result(output)
    }
}

struct MediaPlaybackTool: Tool {
    let descriptor = ToolDescriptor(id: "media.playPause", description: "Play, pause or toggle Spotify using its supported AppleScript interface. Other media applications are not supported.", properties: ["action": textProperty("Playback action", choices: ["play", "pause", "toggle"])], required: ["action"], risk: .reversible, capabilities: [.automation])
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments)
        var action = arguments.object?["action"]?.string ?? ""
        if action == "toggle" {
            let current = try await SpotifyTool().execute(arguments: .object(["action": .string("current")]))
            action = current.summary.lowercased().hasPrefix("playing") ? "pause" : "play"
        }
        return try await SpotifyTool().execute(arguments: .object(["action": .string(action)]))
    }
}
