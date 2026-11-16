enum VoiceTimingLabels {
    static func title(_ key: String) -> String {
        switch key {
        case "activationToMicrophoneReadyMs": "Microphone ready"
        case "activationToFirstPartialMs": "First live words"
        case "microphoneToFirstPartialMs": "Microphone to first words"
        case "inputEndToFinalMs": "Finishing transcription"
        case "activationToFirstActionMs": "First action"
        case "activationToVerifiedCompletionMs": "Task complete"
        default: key
        }
    }
}
