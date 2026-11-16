import Foundation

/// Only the selected input matters to transcription. Output-only notifications
/// must not be mistaken for a microphone disconnect.
struct AudioInputConfiguration: Equatable, Sendable {
    let deviceID: UInt32
    let sampleRate: Double
    let channels: UInt32
    let formatID: UInt32
    let formatFlags: UInt32
    let bytesPerFrame: UInt32
    let bitsPerChannel: UInt32
    var isUsable: Bool { deviceID != 0 && sampleRate.isFinite && sampleRate > 0 && channels > 0 && bytesPerFrame > 0 }
}

struct AudioConfigurationGuard {
    enum Action: Equatable { case ignore, restart, rebuildStartupTap, discard }
    private(set) var expected: AudioInputConfiguration
    private(set) var repairsRemaining: Int
    init(expected: AudioInputConfiguration, repairLimit: Int = 2) {
        self.expected = expected; repairsRemaining = repairLimit
    }
    mutating func evaluate(current: AudioInputConfiguration?, running: Bool, hasAudio: Bool) -> Action {
        guard let current, current.isUsable, current.deviceID == expected.deviceID else { return .discard }
        if current == expected && running { return .ignore }
        // A format change after buffers were accepted could corrupt/truncate speech.
        if current != expected && hasAudio { return .discard }
        guard repairsRemaining > 0 else { return .discard }
        repairsRemaining -= 1
        if current == expected { return .restart }
        expected = current
        return .rebuildStartupTap
    }
}
