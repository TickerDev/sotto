import Foundation
import SottoAudio
import SottoProviders

public struct Preferences: Codable {
    public var activationShortcut = ActivationShortcut.default
    public var appearance = "system"
    public var notifications = false
    public var microphoneUID = ""
    public var microphoneName = ""
    public var language = "en-US"
    public var onDeviceSpeech = true
    public var speechBackend = SpeechBackend.apple
    public var remoteSpeechConsent = false
    public var prepareWhileSpeaking = true
    public var toggleToTalk = false
    public var audioFeedback = false
    public var model = "gpt-4.1-mini"
    public var automaticIntelligence = true
    public var reasoningBackend = ReasoningBackend.openAI
    public var ollamaEndpoint = "http://127.0.0.1:11434"
    public var ollamaModel = ""
    public var remoteConsent = false
    public var historyEnabled = true
    public var retentionDays = 30
    public var setupCompleted = false
    public var setupDismissed = false
    public var firstActionSucceeded = false
    public init() {}
    enum CodingKeys: String, CodingKey { case automaticIntelligence, activationShortcut, shortcut, keyCode, appearance, notifications, microphoneUID, microphoneName, language, onDeviceSpeech, speechBackend, remoteSpeechConsent, prepareWhileSpeaking, pressToToggle, audioFeedback, model, reasoningBackend, ollamaEndpoint, ollamaModel, remoteConsent, historyEnabled, retentionDays, setupCompleted, setupDismissed, firstActionSucceeded, microphone }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = ActivationShortcut.legacy(modifierIndex: try c.decodeIfPresent(Int.self, forKey: .shortcut) ?? 0, keyCode: try c.decodeIfPresent(Int64.self, forKey: .keyCode) ?? 49)
        let saved = try c.decodeIfPresent(ActivationShortcut.self, forKey: .activationShortcut) ?? legacy
        activationShortcut = saved.isValid ? saved : .default
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? self.appearance
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? self.notifications
        microphoneUID = try c.decodeIfPresent(String.self, forKey: .microphoneUID) ?? self.microphoneUID
        microphoneName = try c.decodeIfPresent(String.self, forKey: .microphoneName) ?? self.microphoneName
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? self.language
        onDeviceSpeech = try c.decodeIfPresent(Bool.self, forKey: .onDeviceSpeech) ?? self.onDeviceSpeech
        speechBackend = try c.decodeIfPresent(SpeechBackend.self, forKey: .speechBackend) ?? .apple
        remoteSpeechConsent = try c.decodeIfPresent(Bool.self, forKey: .remoteSpeechConsent) ?? false
        prepareWhileSpeaking = try c.decodeIfPresent(Bool.self, forKey: .prepareWhileSpeaking) ?? true
        toggleToTalk = try c.decodeIfPresent(Bool.self, forKey: .pressToToggle) ?? false
        audioFeedback = try c.decodeIfPresent(Bool.self, forKey: .audioFeedback) ?? self.audioFeedback
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? self.model
        automaticIntelligence = try c.decodeIfPresent(Bool.self, forKey: .automaticIntelligence) ?? false
        reasoningBackend = try c.decodeIfPresent(ReasoningBackend.self, forKey: .reasoningBackend) ?? .openAI
        ollamaEndpoint = try c.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? self.ollamaEndpoint
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? self.ollamaModel
        remoteConsent = try c.decodeIfPresent(Bool.self, forKey: .remoteConsent) ?? self.remoteConsent
        historyEnabled = try c.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? self.historyEnabled
        retentionDays = try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? self.retentionDays
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted) ?? remoteConsent
        setupDismissed = try c.decodeIfPresent(Bool.self, forKey: .setupDismissed) ?? self.setupDismissed
        firstActionSucceeded = try c.decodeIfPresent(Bool.self, forKey: .firstActionSucceeded) ?? self.firstActionSucceeded
        if !c.contains(.microphoneUID), (try c.decodeIfPresent(UInt32.self, forKey: .microphone) ?? 0) != 0 {
            microphoneUID = Microphones.legacySelection
            microphoneName = "Previously selected microphone"
        }
        retentionDays = [1, 7, 30, 90].contains(retentionDays) ? retentionDays : 30
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(activationShortcut, forKey: .activationShortcut)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(notifications, forKey: .notifications)
        try c.encode(microphoneUID, forKey: .microphoneUID)
        try c.encode(microphoneName, forKey: .microphoneName)
        try c.encode(language, forKey: .language)
        try c.encode(onDeviceSpeech, forKey: .onDeviceSpeech)
        try c.encode(speechBackend, forKey: .speechBackend)
        try c.encode(remoteSpeechConsent, forKey: .remoteSpeechConsent)
        try c.encode(prepareWhileSpeaking, forKey: .prepareWhileSpeaking)
        try c.encode(toggleToTalk, forKey: .pressToToggle)
        try c.encode(audioFeedback, forKey: .audioFeedback)
        try c.encode(model, forKey: .model)
        try c.encode(automaticIntelligence, forKey: .automaticIntelligence)
        try c.encode(reasoningBackend, forKey: .reasoningBackend)
        try c.encode(ollamaEndpoint, forKey: .ollamaEndpoint)
        try c.encode(ollamaModel, forKey: .ollamaModel)
        try c.encode(remoteConsent, forKey: .remoteConsent)
        try c.encode(historyEnabled, forKey: .historyEnabled)
        try c.encode(retentionDays, forKey: .retentionDays)
        try c.encode(setupCompleted, forKey: .setupCompleted)
        try c.encode(setupDismissed, forKey: .setupDismissed)
        try c.encode(firstActionSucceeded, forKey: .firstActionSucceeded)
    }
    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "preferences"), let result = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return result
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "preferences") }
}
