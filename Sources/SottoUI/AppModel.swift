import AppKit
import Observation
import ServiceManagement
import UserNotifications
import SottoAgent
import SottoAudio
import SottoTools
import SottoSecurity
import SottoProviders
import SottoIntegrations
import SottoPersistence
import OSLog

@Observable @MainActor public final class AppModel {
    private var machine = AgentStateMachine()
    public var state: AgentState {
        get { machine.state }
        set { _ = machine.transition(to: newValue) }
    }
    public var settingsSection = "General"
    public var status = "Just say it. It’s done."
    public var transcript = ""
    public private(set) var confirmedSpeech = ""
    public private(set) var provisionalSpeech = ""
    public private(set) var voiceTimings: [String: Double] = [:]
    private var voiceLatency: VoiceLatencyTrace?
    private var speechResourceCheck: Task<Void, Never>?
    public private(set) var modernSpeechReady = false
    private let voicePreparation = VoicePreparationController()
    private var awaitingVoicePreparation: Task<PreparedAgentTurn?, Never>?
    public var reply = ""
    public private(set) var fileMatches: [FileSearchMatch] = []
    public private(set) var confirmedSummary = ""
    public var levels = [Float](repeating: 0, count: 36)
    public private(set) var voiceActivation: VoiceActivation = .button
    public let pendingIntelligence = PendingIntelligenceRequest()
    public var intelligenceSetupPresented = false
    public private(set) var intelligenceConnecting = false
    public private(set) var intelligenceSetupMessage: String?
    private var intelligenceSetupTask: Task<Void, Never>?
    private var intelligenceSetupExpiry: Task<Void, Never>?
    private var intelligenceSetupOperation = UUID()
    public var integrationRequest: IntegrationAccessRequest?
    private var integrationContinuation: CheckedContinuation<Result<Void, IntegrationAccessError>, Never>?
    private var integrationExpiry: Task<Void, Never>?
    public var approval: Approval?
    public var paused = false
    public var activities: [Activity] = []
    public var error: String?
    public var shortcutAvailable = false
    public private(set) var isEditingShortcut = false
    #if DEBUG
    public var shortcutCapturePurpose: CapturePurpose = .command
    #endif
    public let providerConnection: ProviderConnection
    public let localRuntime: ManagedOllamaRuntime
    private let managesLocalRuntime: Bool
    public let localProviderConnection: LocalProviderConnection
    public var credentialStatus: String { providerConnection.status }
    public var models: [ModelInfo] { providerConnection.models }
    public let discovery = CapabilityDiscovery()
    public let microphones: MicrophoneCatalog
    public let permissions = PermissionCenter()
    public var hasSavedKey: Bool { providerConnection.hasSavedKey }
    public var providerVerified: Bool { settings.reasoningBackend == .openAI ? providerConnection.verified : localProviderConnection.isVerified(settings.ollamaModel) }
    public var providerChecking: Bool { settings.reasoningBackend == .openAI ? providerConnection.isChecking : localProviderConnection.isChecking }
    public var hasProviderConfiguration: Bool { settings.reasoningBackend == .openAI ? hasSavedKey || providerConnection.inspectionFailed : !settings.ollamaModel.isEmpty && (try? OllamaEndpoint(settings.ollamaEndpoint)) != nil }
    public var processingAllowed: Bool { !settings.reasoningBackend.requiresRemoteConsent || settings.remoteConsent }
    public var credentialSaving: Bool { providerConnection.isSaving }
    public var canVerifyProvider: Bool { providerConnection.canVerify }
    public private(set) var voiceCheck: VoiceCheckState = .idle
    public private(set) var spotifyConnection: SpotifyConnectionState = .unchecked
    private var spotifyCheckTask: Task<Void, Never>?
    public private(set) var capturePurpose: CapturePurpose = .command
    public private(set) var recovery: RecoveryAction?
    public private(set) var activeMicrophone: Microphone?
    private var activationObserver: NSObjectProtocol?
    private var sleptObserver: NSObjectProtocol?
    public var settings = Preferences.load() {
        didSet {
            if persistPreferences { settings.save() }
            if settings.activationShortcut != oldValue.activationShortcut { configureShortcut() }
            if settings.appearance != oldValue.appearance { applyAppearance() }
            if settings.model != oldValue.model { providerConnection.invalidate() }
            if settings.ollamaEndpoint != oldValue.ollamaEndpoint { localProviderConnection.invalidate(); localRuntime.shutdown() }
            if settings.ollamaModel != oldValue.ollamaModel { localProviderConnection.select(settings.ollamaModel) }
            if settings.automaticIntelligence != oldValue.automaticIntelligence || (oldValue.remoteConsent && !settings.remoteConsent) || settings.reasoningBackend != oldValue.reasoningBackend || settings.ollamaEndpoint != oldValue.ollamaEndpoint || settings.ollamaModel != oldValue.ollamaModel || settings.model != oldValue.model {
                cancel(clearPendingIntelligence: !settings.remoteConsent && oldValue.remoteConsent); context = []; archivedConversations = [] // Never carry private conversation context to a different provider/model.
            }
            if settings.reasoningBackend != oldValue.reasoningBackend { if localProviderConnection.isChecking { localProviderConnection.cancel() }; if providerConnection.isChecking { providerConnection.cancelVerification(showStatus: false) } }
            if settings.microphoneUID != oldValue.microphoneUID { checkAudioRoute() }
            if settings.speechBackend != oldValue.speechBackend || settings.remoteSpeechConsent != oldValue.remoteSpeechConsent || settings.language != oldValue.language || settings.onDeviceSpeech != oldValue.onDeviceSpeech {
                cancel()
            }
            if settings.toggleToTalk != oldValue.toggleToTalk { cancel(); configureShortcut() }
            if settings.prepareWhileSpeaking != oldValue.prepareWhileSpeaking { voicePreparation.cancel() }
        }
    }
    public var present: (() -> Void)?
    public var dismiss: (() -> Void)?
    public var openSettings: (() -> Void)?
    private var speech: any SpeechRecognitionProvider
    private let usesInjectedSpeech: Bool
    public var voicePermissionsAllowed: Bool {
        permissions.state(.microphone) == .allowed && (modernSpeechReady || !speech.requiresSpeechAuthorization || settings.speechBackend == .openAIRealtime || permissions.state(.speech) == .allowed)
    }
    private var unavailableMicrophones: Set<String> = []
    private var microphoneRecoveries = 0
    private var retriedPreferredMicrophone = false
    private var captureDeadline: ContinuousClock.Instant?
    private let shortcut = GlobalShortcut()
    private let gate = AuthorizationGate()
    private let runtime: AgentRuntime
    private var store: ActivityStore?
    private var task: Task<Void, Never>?
    private var autoDismiss: Task<Void, Never>?
    public private(set) var autoDismissWindow: AutoDismissWindow?
    private var contextExpiry: Task<Void, Never>?
    private var recordingLimit: Task<Void, Never>?
    private var wantsListening = false
    private var recordingReady = false
    private var sessionID = UUID()
    private var context: [JSONValue] = []
    private var archivedConversations: [[JSONValue]] = []
    private var lastInteraction = Date.distantPast
    private func archiveActiveConversation() {
        guard !context.isEmpty else { return }
        archivedConversations.append(context)
        if archivedConversations.count > 3 { archivedConversations.removeFirst(archivedConversations.count - 3) }
        context = []
    }
    private var hadFailure = false
    private var hasReadableResult = false
    private var evidence = ""
    @ObservationIgnored private let persistPreferences: Bool
    @ObservationIgnored private let onDeviceAvailable: @MainActor () -> Bool
    public init(providerConnection: ProviderConnection = ProviderConnection(), localProviderConnection: LocalProviderConnection = LocalProviderConnection(), preferences: Preferences? = nil, startServices: Bool = true, onDeviceAvailable: @escaping @MainActor () -> Bool = { OnDeviceIntelligence.available }, registry: ToolRegistry = NativeTools.registry(), microphones: MicrophoneCatalog = MicrophoneCatalog(), speech: (any SpeechRecognitionProvider)? = nil, localRuntime: ManagedOllamaRuntime? = nil) {
        self.localRuntime = localRuntime ?? ManagedOllamaRuntime(); self.managesLocalRuntime = startServices || localRuntime != nil
        self.microphones = microphones; self.speech = speech ?? AppleSpeechProvider(); self.usesInjectedSpeech = speech != nil
        self.providerConnection = providerConnection; self.localProviderConnection = localProviderConnection
        self.persistPreferences = startServices; self.onDeviceAvailable = onDeviceAvailable
        if let preferences { settings = preferences }
        runtime = AgentRuntime(registry: registry, gate: gate)
        microphones.changed = { [weak self] in self?.checkAudioRoute() }
        guard startServices else { return }
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Sotto")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            store = try ActivityStore(path: folder.appendingPathComponent("activity.sqlite").path)
        } catch { self.error = "History unavailable: \(error.localizedDescription)" }
        Task { [weak self] in
            guard let self else { return }
            await providerConnection.inspectSavedKey()
            await localProviderConnection.refresh(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
        }
        permissions.changed = { [weak self] in self?.checkVoicePermissions() }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { @Sendable [weak self] _ in
            Task { @MainActor in self?.refreshEnvironment() }
        }
        sleptObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, [.listening, .transcribing].contains(self.state) else { return }
                self.abortCapture("Your Mac went to sleep. Recording was discarded; start again after waking.")
            }
        }
        shortcut.pressed = { [weak self] in
            guard let self, !self.paused, !self.isEditingShortcut else { return false }
            if self.settings.toggleToTalk && self.state == .listening { self.endListening(); return true }
            if self.isBusy { self.cancel(); return false }
            #if DEBUG
            self.beginListening(activation: self.settings.toggleToTalk ? .toggleShortcut : .heldShortcut, purpose: self.shortcutCapturePurpose)
            #else
            self.beginListening(activation: self.settings.toggleToTalk ? .toggleShortcut : .heldShortcut)
            #endif
            return self.state == .listening
        }
        shortcut.released = { [weak self] in guard let self, self.voiceActivation == .heldShortcut else { return }; self.endListening() }
        shortcut.handsFree = { [weak self] in
            guard let self, self.state == .listening, self.voiceActivation == .heldShortcut else { return }
            self.voiceActivation = .handsFreeShortcut
            Logger(subsystem: "org.sotto.mac", category: "keyboard").notice("Hands-free recording latched")
        }
        shortcut.cancelled = { [weak self] in self?.cancel() }
        permissions.keyboardListenerReady = { [weak shortcut] in shortcut?.available ?? false }
        configureShortcut(); applyAppearance(); Task { await refreshHistory() }
    }
    public func configureShortcut() {
        guard !isEditingShortcut else { return }
        shortcut.binding = settings.activationShortcut
        shortcut.toggleMode = settings.toggleToTalk
        shortcut.start(); shortcutAvailable = shortcut.available
        permissions.refresh()
    }
    public var shortcutStatus: String {
        isEditingShortcut ? "Recording shortcut…" : permissions.keyboard.shortcutLabel
    }
    func beginShortcutEditing() -> Bool {
        guard !isBusy, !isEditingShortcut else { return false }
        isEditingShortcut = true; shortcut.stop(); shortcutAvailable = false
        return true
    }
    func finishShortcutEditing(_ binding: ActivationShortcut?) {
        guard isEditingShortcut else { return }
        isEditingShortcut = false
        if let binding, binding.isValid, binding != settings.activationShortcut { settings.activationShortcut = binding }
        else { configureShortcut() }
    }
    public func applyAppearance() { NSApp.appearance = settings.appearance == "system" ? nil : NSAppearance(named: settings.appearance == "dark" ? .darkAqua : .aqua) }
    public func activate() { if state == .listening { endListening() } else { beginListening() } }
    public func beginListening(activation: VoiceActivation = .button, purpose: CapturePurpose = .command) {
        fileMatches = []
        beginCapture(activation: activation, purpose: purpose, recovering: false)
    }
    private func beginCapture(activation: VoiceActivation, purpose: CapturePurpose, recovering: Bool) {
        guard !paused, [.idle, .completed, .failed, .responded, .awaitingInput].contains(state) else { return }
        if settings.speechBackend == .openAIRealtime && !settings.remoteSpeechConsent {
            fail("Allow audio processing by OpenAI in Voice settings before using Realtime transcription.", recovery: .voiceSettings)
            return
        }
        if !recovering {
            unavailableMicrophones = []; microphoneRecoveries = 0; retriedPreferredMicrophone = false
            captureDeadline = ContinuousClock.now.advanced(by: .seconds(55))
            let started = activation == .button ? ProcessInfo.processInfo.systemUptime : shortcut.activationTimestamp ?? ProcessInfo.processInfo.systemUptime
            voiceLatency = VoiceLatencyTrace(started: started); voiceTimings = [:]
        }
        cancelIntelligenceSetup()
        let activationTime = ContinuousClock.now
        if Date().timeIntervalSince(lastInteraction) > 300 { context = []; archivedConversations = [] }
        else if state == .idle { archiveActiveConversation() }
        lastInteraction = Date()
        scheduleContextExpiry()
        cancelAutoDismiss(); task?.cancel(); speech.cancel(); sessionID = UUID(); let id = sessionID
        if !usesInjectedSpeech {
            if settings.speechBackend == .apple { speech = AppleSpeechProvider() }
            else {
                speech = OpenAIRealtimeSpeechProvider { [providerConnection] in try await providerConnection.readKey() }
            }
        }
        let sessionSpeech = speech
        voiceActivation = activation; capturePurpose = purpose; recovery = nil; activeMicrophone = nil
        voicePreparation.cancel()
        if settings.prepareWhileSpeaking && purpose == .command {
            voicePreparation.begin { [weak self] text in await self?.prepareVoiceTurn(text) }
        }
        if purpose == .voiceCheck { context = [] }
        if purpose == .voiceCheck { voiceCheck = .checking }
        wantsListening = true; recordingReady = false; transcript = ""; confirmedSpeech = ""; provisionalSpeech = ""; reply = ""; confirmedSummary = ""; levels = Array(repeating: 0, count: 36)
        state = .listening; status = "Starting microphone…"; present?()
        Logger(subsystem: "org.sotto.mac", category: "latency").notice("Activation to panel ordering: \(String(describing: activationTime.duration(to: .now)), privacy: .public)")
        task = Task { [self] in
            do {
                guard sessionID == id, !Task.isCancelled else { return }
                if recovering && !wantsListening {
                    abortCapture("The microphone changed before recording was ready. Activate Sotto again when you’re ready.")
                    return
                }
                let selected = try microphones.selected(settings.microphoneUID, excluding: unavailableMicrophones)
                activeMicrophone = selected
                try await sessionSpeech.start(locale: settings.language, deviceID: selected.deviceID, onDevice: settings.onDeviceSpeech) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id, self.state == .listening else { return }
                        switch update { case .level(let value): self.levels.removeFirst(); self.levels.append(value); self.voicePreparation.audio(value)
                        case .transcript(let text): self.transcript = text; self.provisionalSpeech = text; self.confirmedSpeech = ""; self.heardSpeech(text, provisional: !text.isEmpty)
                        case .hypothesis(let value): self.transcript = value.text; self.confirmedSpeech = value.confirmed; self.provisionalSpeech = value.provisional; self.heardSpeech(value.text, provisional: !value.provisional.isEmpty)
                        case .failure(let text): self.abortCapture(text)
                        case .inputUnavailable: self.adaptMicrophone() }
                    }
                }
                guard sessionID == id else { return }; permissions.refresh(); recordingReady = true; status = recovering ? "Listening on \(selected.name) · Please repeat" : "Listening on \(selected.name)"
                recordVoiceTiming(.microphoneReady)
                recordingLimit?.cancel()
                recordingLimit = Task { [weak self] in
                    guard let deadline = self?.captureDeadline else { return }
                    try? await Task.sleep(until: deadline, clock: .continuous)
                    guard !Task.isCancelled, let self, self.sessionID == id else { return }
                    self.abortCapture("Recording reached its 55-second limit and was discarded. Start again when ready.")
                }
                if settings.audioFeedback { NSSound(named: "Tink")?.play() }
                if !wantsListening { finishRecording(id: id) }
            } catch {
                guard sessionID == id, !Task.isCancelled else { return }
                if case SpeechError.microphoneUnavailable = error { adaptMicrophone() }
                else { fail(error) }
            }
        }
    }
    public func endListening() { guard state == .listening else { return }; shortcut.resetGesture(); wantsListening = false; if recordingReady { finishRecording(id: sessionID) } }
    private func finishRecording(id: UUID) {
        recordVoiceTiming(.inputEnded)
        recordingLimit?.cancel(); state = .transcribing; status = "Finishing transcription"
        let sessionSpeech = speech
        task = Task { [self] in
            do {
                let text = try await sessionSpeech.finish(); sessionSpeech.cancel()
                guard sessionID == id, !Task.isCancelled else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.invalid("No speech heard. Try again.") }
                transcript = text; confirmedSpeech = text; provisionalSpeech = ""; activeMicrophone = nil
                recordVoiceTiming(.finalTranscript)
                if capturePurpose == .voiceCheck {
                    voiceCheck = .passed; state = .thinking; state = .responded
                    status = "Voice check complete"; reply = text; present?()
                } else { submit(text) }
            } catch { if sessionID == id && !Task.isCancelled { fail(error) } }
        }
    }
    public var canRunVoiceCheckCommand: Bool {
        capturePurpose == .voiceCheck && state == .responded && voiceCheck == .passed &&
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public func runVoiceCheckCommand() {
        guard canRunVoiceCheckCommand else { return }
        let text = transcript
        task?.cancel(); sessionID = UUID()
        capturePurpose = .command; state = .thinking; status = "Thinking"; reply = ""
        lastInteraction = Date(); scheduleContextExpiry(); present?()
        // This explicit user action uses the same consent, credential, tool and
        // approval path as a normal spoken command. A microphone test never sends itself.
        submit(text)
    }
    public func submit(_ text: String) {
        submit(text, nativeAction: nil, fromVoice: state == .transcribing)
    }
    public func openFileMatch(_ match: FileSearchMatch, reveal: Bool = false) {
        guard fileMatches.contains(match), !isBusy else { return }
        submit(reveal ? "Reveal \(match.name) in Finder" : "Open \(match.name)", nativeAction: .fileAction(path: match.path, reveal: reveal))
    }
    private func submit(_ text: String, nativeAction: NativeCommandProvider?, fromVoice: Bool = false) {
        guard !paused else { return }
        let prepared = fromVoice ? voicePreparation.take(for: text) : nil
        awaitingVoicePreparation?.cancel(); awaitingVoicePreparation = prepared
        if !fromVoice { voicePreparation.cancel(); voiceLatency = nil }
        cancelIntelligenceSetup()
        if let request = integrationRequest { resolveIntegration(request.id, allowed: false) }
        task?.cancel(); cancelAutoDismiss(); sessionID = UUID(); let id = sessionID
        confirmedSummary = ""; recovery = nil
        fileMatches = []
        let startedIdle = state == .idle
        let backend = settings.reasoningBackend, model = settings.model, localModel = settings.ollamaModel, endpoint = settings.ollamaEndpoint
        task = Task { [self] in
            var usingLocalRuntime = false
            defer { prepared?.cancel(); if sessionID == id { awaitingVoicePreparation = nil } }
            defer { if usingLocalRuntime { localRuntime.endUse() } }
            do {
                if startedIdle { archiveActiveConversation() }
                let provider: any ReasoningProvider
                var providerKey = ""
                if let native = nativeAction ?? NativeCommandProvider(command: text) {
                    archiveActiveConversation(); provider = native; providerKey = voiceProviderKey("native")
                } else if settings.automaticIntelligence {
                    if onDeviceAvailable() {
                        #if canImport(FoundationModels)
                        if #available(macOS 26, *) { provider = OnDeviceProvider(); providerKey = voiceProviderKey("apple") }
                        else { throw ToolError.unavailable("On-device intelligence requires a newer macOS.") }
                        #else
                        throw ToolError.unavailable("On-device intelligence is unavailable in this build.")
                        #endif
                    } else {
                        if managesLocalRuntime {
                            do {
                                state = .thinking; status = "Starting local intelligence…"; transcript = text; present?()
                                localRuntime.beginUse(); usingLocalRuntime = true
                                try await localRuntime.ensureRunning(endpoint: endpoint)
                                await localProviderConnection.refresh(endpoint: endpoint, model: localModel)
                            } catch is CancellationError { throw CancellationError() }
                            catch { localProviderConnection.invalidate() }
                        }
                        guard let local = localProviderConnection.models.first(where: { $0.supportsTools }) else { offerIntelligenceSetup(for: text); return }
                        provider = try OllamaProvider(endpoint: endpoint, model: local.id)
                    providerKey = voiceProviderKey("ollama|\(endpoint)|\(local.id)")
                    }
                } else {
                switch backend {
                case .openAI:
                    guard settings.remoteConsent else { offerIntelligenceSetup(for: text); return }
                    guard let key = try await providerConnection.readKey(), !key.isEmpty else { offerIntelligenceSetup(for: text); return }
                    provider = providerConnection.reasoningProvider(key: key, model: model)
                    providerKey = voiceProviderKey("openai|\(model)")
                case .ollama:
                    if managesLocalRuntime {
                        state = .thinking; status = "Starting local intelligence…"; transcript = text; present?()
                        localRuntime.beginUse(); usingLocalRuntime = true
                        try await localRuntime.ensureRunning(endpoint: endpoint)
                        await localProviderConnection.refresh(endpoint: endpoint, model: localModel)
                    }
                    guard localProviderConnection.isVerified(localModel) else { offerIntelligenceSetup(for: text); return }
                    provider = try OllamaProvider(endpoint: endpoint, model: localModel)
                    providerKey = voiceProviderKey("ollama|\(endpoint)|\(localModel)")
                }
                }
                try Task.checkCancellation()
                guard sessionID == id else { return }
                if Date().timeIntervalSince(lastInteraction) > 300 { context = []; archivedConversations = [] }
                else if context.count > 100 { context = [] }
                hadFailure = false; hasReadableResult = false; evidence = ""; confirmedSummary = ""; reply = ""; transcript = text; state = .thinking; status = "Thinking"; present?()
                let firstStep = await withTaskCancellationHandler { await prepared?.value } onCancel: { prepared?.cancel() }
                try Task.checkCancellation()
                guard sessionID == id else { return }
                let resultContext = try await runtime.run(text, context: context, previousConversations: archivedConversations, provider: provider, prepared: firstStep, providerKey: providerKey, prepare: { [weak self] descriptor in
                    try await self?.prepareIntegration(descriptor)
                }) { [weak self] event in
                    await self?.receive(event, id: id)
                }
                guard sessionID == id, !Task.isCancelled else { return }
                context = resultContext; lastInteraction = Date()
                scheduleContextExpiry()
                if state == .awaitingInput { return }
                state = hadFailure ? .failed : evidence.isEmpty ? .responded : .completed
                status = hadFailure ? "An action could not finish" : evidence.isEmpty ? "Sotto" : "Done"
                if !hadFailure && !evidence.isEmpty { recordVoiceTiming(.verifiedCompletion) }
                if !hadFailure && !fileMatches.isEmpty { status = "Found \(fileMatches.count) \(fileMatches.count == 1 ? "file" : "files")" }
                if reply.isEmpty { reply = evidence }
                if settings.audioFeedback { NSSound(named: hadFailure ? "Basso" : "Pop")?.play() }
                if settings.notifications && !evidence.isEmpty { notify(evidence) }
                // Keep long results readable; only short confirmations and replies disappear automatically.
                if !hasReadableResult && !hadFailure && (!evidence.isEmpty || !reply.isEmpty) && reply.count < 280 && evidence.count < 180 { scheduleDismiss() }
            } catch { if sessionID == id && !Task.isCancelled { fail(error) } }
        }
    }
    private func offerIntelligenceSetup(for text: String) {
        contextExpiry?.cancel()
        let id = pendingIntelligence.preserve(text, context: context)
        state = .failed; status = "Intelligence needed"; reply = "Connect intelligence to continue this request. Basic commands still work on this Mac."
        intelligenceSetupMessage = nil; intelligenceSetupPresented = true
        settingsSection = "Intelligence"; openSettings?()
        intelligenceSetupExpiry?.cancel()
        intelligenceSetupExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled, let self, pendingIntelligence.intent?.id == id else { return }
            cancelIntelligenceSetup()
            fail("The waiting request expired. Start a new request when you’re ready.")
        }
    }
    private func heardSpeech(_ text: String, provisional: Bool) {
        if provisional { recordVoiceTiming(.firstPartial) }
        voicePreparation.transcript(text)
    }
    private func recordVoiceTiming(_ phase: VoiceLatencyTrace.Phase) {
        guard var trace = voiceLatency else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard trace.record(phase, at: now) else { return }
        voiceLatency = trace; voiceTimings = trace.milliseconds
        Logger(subsystem: "org.sotto.mac", category: "voice-timing").notice("\(phase.rawValue, privacy: .public) activation ms: \((now - trace.started) * 1000)")
        if phase == .finalTranscript, let interval = voiceTimings["inputEndToFinalMs"] {
            Logger(subsystem: "org.sotto.mac", category: "voice-timing").notice("Input end to final transcript ms: \(interval)")
        }
    }
    private func voiceProviderKey(_ identity: String) -> String {
        identity + "|day:" + String(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
    }
    private func prepareVoiceTurn(_ text: String) async -> PreparedAgentTurn? {
        guard !Task.isCancelled, state == .listening, capturePurpose == .command, settings.prepareWhileSpeaking else { return nil }
        let snapshot = settings, context = self.context, archived = self.archivedConversations
        do {
            let provider: any ReasoningProvider
            let key: String
            if snapshot.automaticIntelligence && onDeviceAvailable() {
                #if canImport(FoundationModels)
                if #available(macOS 26, *) { provider = OnDeviceProvider(); key = voiceProviderKey("apple") }
                else { return nil }
                #else
                return nil
                #endif
            } else if snapshot.automaticIntelligence {
                guard let local = localProviderConnection.models.first(where: { $0.supportsTools }) else { return nil }
                provider = try OllamaProvider(endpoint: snapshot.ollamaEndpoint, model: local.id)
                key = voiceProviderKey("ollama|\(snapshot.ollamaEndpoint)|\(local.id)")
            } else if snapshot.reasoningBackend == .openAI {
                guard snapshot.remoteConsent, providerConnection.hasSavedKey, let secret = try await providerConnection.readKey(), !secret.isEmpty else { return nil }
                provider = providerConnection.reasoningProvider(key: secret, model: snapshot.model)
                key = voiceProviderKey("openai|\(snapshot.model)")
            } else {
                guard localProviderConnection.isVerified(snapshot.ollamaModel) else { return nil }
                provider = try OllamaProvider(endpoint: snapshot.ollamaEndpoint, model: snapshot.ollamaModel)
                key = voiceProviderKey("ollama|\(snapshot.ollamaEndpoint)|\(snapshot.ollamaModel)")
            }
            try Task.checkCancellation()
            return try await runtime.prepareTurn(text, context: context, previousConversations: archived, provider: provider, providerKey: key)
        } catch { return nil } // Preparation failure never blocks the confirmed request.
    }
    public func showIntelligenceSetup() {
        guard !isBusy else { return }
        intelligenceSetupMessage = nil; intelligenceSetupPresented = true
    }
    public func enableLocalIntelligence() {
        guard !intelligenceConnecting, !isBusy else { return }
        intelligenceConnecting = true; intelligenceSetupMessage = nil
        let operation = intelligenceSetupOperation, pendingID = pendingIntelligence.intent?.id
        intelligenceSetupTask = Task { [weak self] in
            guard let self else { return }
            localRuntime.beginUse()
            defer { localRuntime.endUse() }
            do {
                try await localRuntime.ensureRunning(endpoint: settings.ollamaEndpoint)
                await localProviderConnection.refresh(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
                try Task.checkCancellation()
                guard intelligenceSetupOperation == operation else { return }
                intelligenceConnecting = false
                guard let selected = localProviderConnection.models.first(where: { $0.supportsTools }) else {
                    intelligenceSetupMessage = "Local intelligence is running, but no compatible model is installed. Model download setup is not available in this build yet."
                    return
                }
                var updated = settings
                updated.automaticIntelligence = false; updated.reasoningBackend = .ollama
                updated.ollamaModel = localProviderConnection.isVerified(settings.ollamaModel) ? settings.ollamaModel : selected.id
                settings = updated
                finishIntelligenceSetup(pendingID: pendingID, verified: true, includeContext: true)
            } catch {
                guard intelligenceSetupOperation == operation else { return }
                intelligenceConnecting = false; intelligenceSetupMessage = error.localizedDescription
            }
        }
    }
    public func checkIntelligenceForSetup() {
        guard !intelligenceConnecting else { return }
        intelligenceConnecting = true
        let operation = intelligenceSetupOperation
        intelligenceSetupTask = Task { [weak self] in
            guard let self else { return }
            await localProviderConnection.refresh(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
            guard !Task.isCancelled, intelligenceSetupOperation == operation else { return }
            refreshEnvironment(); intelligenceConnecting = false
            intelligenceSetupMessage = onDeviceAvailable() || localProviderConnection.models.contains(where: \.supportsTools)
                ? "Intelligence is ready. Choose Use to continue." : "No compatible intelligence is ready. You can connect OpenAI API below, or keep using basic commands."
        }
    }
    public func useAvailableIntelligence() {
        guard !intelligenceConnecting, onDeviceAvailable() || localProviderConnection.models.contains(where: \.supportsTools) else { return }
        let pendingID = pendingIntelligence.intent?.id
        settings.automaticIntelligence = true
        finishIntelligenceSetup(pendingID: pendingID, verified: true, includeContext: true)
    }
    public func connectIntelligence(key: String, remoteConsent: Bool) {
        guard remoteConsent, !intelligenceConnecting else { return }
        intelligenceConnecting = true; intelligenceSetupMessage = nil
        let operation = intelligenceSetupOperation
        let pendingID = pendingIntelligence.intent?.id
        let selectedModel = settings.model
        intelligenceSetupTask = Task { [weak self] in
            guard let self else { return }
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await providerConnection.saveKey(key.trimmingCharacters(in: .whitespacesAndNewlines)).value
                guard !Task.isCancelled, intelligenceSetupOperation == operation else { return }
                guard providerConnection.lastSaveSucceeded else {
                    intelligenceConnecting = false; intelligenceSetupMessage = providerConnection.status
                    return
                }
            }
            guard !Task.isCancelled, intelligenceSetupOperation == operation else { return }
            await providerConnection.verify(model: selectedModel)
            guard !Task.isCancelled, intelligenceSetupOperation == operation else { return }
            intelligenceConnecting = false
            guard providerConnection.verified, selectedModel == settings.model else {
                intelligenceSetupMessage = providerConnection.status
                return
            }
            // This explicit action authorizes future API use. Verification itself
            // only reads the catalog; no billable generation precedes this consent.
            var updated = settings
            updated.reasoningBackend = .openAI; updated.automaticIntelligence = false; updated.remoteConsent = true
            settings = updated
            // Only this explicit consent may restore the waiting request’s context.
            finishIntelligenceSetup(pendingID: pendingID, verified: providerConnection.verified, includeContext: true)
        }
    }
    private func finishIntelligenceSetup(pendingID: UUID?, verified: Bool, includeContext: Bool) {
        guard verified else { return }
        let intent = pendingID.flatMap { pendingIntelligence.take($0, connectionVerified: verified) }
        intelligenceSetupExpiry?.cancel(); intelligenceSetupExpiry = nil
        intelligenceSetupPresented = false
        if let intent {
            let continuationContext = includeContext ? intent.context : []
            context = continuationContext
            submit(intent.text)
        } else if pendingID != nil {
            intelligenceSetupMessage = "Your waiting request expired. Start a new request."
        }
    }
    public func cancelIntelligenceSetup() {
        let hadPendingRequest = pendingIntelligence.intent != nil
        intelligenceSetupOperation = UUID()
        intelligenceSetupTask?.cancel(); intelligenceSetupTask = nil
        intelligenceSetupExpiry?.cancel(); intelligenceSetupExpiry = nil
        if intelligenceConnecting { providerConnection.cancelVerification(showStatus: false); localProviderConnection.cancel() }
        intelligenceConnecting = false; intelligenceSetupPresented = false
        intelligenceSetupMessage = nil; pendingIntelligence.discard()
        if hadPendingRequest {
            context = []; transcript = ""; reply = ""; state = .idle; status = "Cancelled"
        }
    }
    private func receive(_ event: AgentEvent, id: UUID) async {
        guard sessionID == id else {
            if case .result(let name, let result) = event { await record(name, result.summary, true) }
            if case .failure(let name, let text) = event { await record(name, text, false) }
            return
        }
        switch event {
        case .state(let state, let text): self.state = state; status = text; reply = ""; if state == .executing { recordVoiceTiming(.firstAction) }
        case .text(let text): reply += text
        case .approval(let request): approval = request; state = .awaitingApproval; status = "Approve this action"; present?()
        case .question(let question):
            if !fileMatches.isEmpty { state = .responded; status = "Choose a file"; reply = "" }
            else { state = .awaitingInput; status = "A quick question"; reply = question }
            present?()
        case .result(let name, let result):
            if name == "open_file" { fileMatches = [] }
            if result.data.object?["agenda"] != nil { hasReadableResult = true }
            if name == "find_files", let matches = FileSearchResults.decode(result.data) {
                fileMatches = Array(matches.files.prefix(20))
                hasReadableResult = true
            }
            settings.firstActionSucceeded = true; evidence = result.summary; confirmedSummary = result.summary; await record(name, result.summary, true)
        case .failure(let name, let text): hadFailure = true; await record(name, text, false)
        }
    }
    public func resolveApproval(_ allowed: Bool) {
        guard let request = approval else { return }; approval = nil
        Task { await gate.resolve(request.id, allowed: allowed) }
    }
    private func prepareIntegration(_ descriptor: ToolDescriptor) async throws {
        let kind: PermissionKind
        if descriptor.capabilities.contains(.calendar) { kind = .calendar }
        else if descriptor.capabilities.contains(.reminders) { kind = .reminders }
        else { return }
        permissions.refresh()
        guard permissions.state(kind) != .allowed else { return }
        guard integrationContinuation == nil else { throw ToolError.denied("Another connection is awaiting access.") }
        let request = IntegrationAccessRequest(kind: kind)
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                integrationContinuation = continuation
                integrationRequest = request
                state = .awaitingApproval; status = "Connect \(kind.title)"
                settingsSection = "Integrations"; openSettings?()
                integrationExpiry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(300))
                    if !Task.isCancelled { self?.resolveIntegration(request.id, allowed: false) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.resolveIntegration(request.id, allowed: false) } }
        try Task.checkCancellation()
        permissions.refresh()
        try outcome.get()
        guard permissions.state(kind) == .allowed else { throw IntegrationAccessError.notGranted(kind.title) }
    }
    public func connectIntegration(_ id: UUID) async {
        guard let request = integrationRequest, request.id == id else { return }
        let outcome = await permissions.request(request.kind)
        guard integrationRequest?.id == id else { return }
        let result: Result<Void, IntegrationAccessError> = switch outcome {
        case .allowed: .success(())
        case .notGranted: .failure(.notGranted(request.kind.title))
        case .settingsRequired: .failure(.settingsRequired(request.kind.title))
        case .unavailable: .failure(.unavailable(request.kind.title))
        case .busy: .failure(.busy)
        }
        finishIntegration(id, result: result)
    }
    public func resolveIntegration(_ id: UUID, allowed: Bool) {
        finishIntegration(id, result: allowed ? .success(()) : .failure(.cancelled))
    }
    private func finishIntegration(_ id: UUID, result: Result<Void, IntegrationAccessError>) {
        guard integrationRequest?.id == id, let continuation = integrationContinuation else { return }
        integrationContinuation = nil; integrationRequest = nil
        integrationExpiry?.cancel(); integrationExpiry = nil
        continuation.resume(returning: result)
    }
    public func cancel(clearPendingIntelligence: Bool = true) {
        voicePreparation.cancel()
        awaitingVoicePreparation?.cancel(); awaitingVoicePreparation = nil
        if clearPendingIntelligence { cancelIntelligenceSetup() }
        if let request = integrationRequest { resolveIntegration(request.id, allowed: false) }
        shortcut.resetGesture()
        sessionID = UUID(); recordingLimit?.cancel(); wantsListening = false; activeMicrophone = nil; recovery = nil;
        if voiceCheck == .checking { voiceCheck = .idle }
        task?.cancel(); task = nil; speech.cancel(); cancelAutoDismiss()
        if let approval { Task { await gate.resolve(approval.id, allowed: false) } }; approval = nil
        archiveActiveConversation()
        transcript = ""; reply = ""; confirmedSummary = ""; state = .idle; status = "Cancelled"; dismiss?()
        fileMatches = []
    }
    private func fail(_ error: Error) {
        if error is DecodingError {
            fail(IntelligenceResponseError.unreadableResponse.localizedDescription, recovery: .providerSettings)
            return
        }
        let action: RecoveryAction?
        switch error {
        case SpeechError.microphonePermission: action = .permission(.microphone)
        case SpeechError.speechPermission: action = .permission(.speech)
        case SpeechError.message: action = settings.speechBackend == .openAIRealtime ? .voiceSettings : nil
        case SpeechError.microphoneUnavailable, SpeechError.onDeviceUnavailable, SpeechError.recognitionUnavailable: action = .voiceSettings
        case is IntelligenceResponseError: action = .providerSettings
        case ToolError.denied: action = .providerSettings
        default: action = nil
        }
        fail(error.localizedDescription, recovery: action)
    }
    private func fail(_ text: String, recovery: RecoveryAction? = nil) {
        voicePreparation.cancel()
        awaitingVoicePreparation?.cancel(); awaitingVoicePreparation = nil
        shortcut.resetGesture()
        speech.cancel(); activeMicrophone = nil; self.recovery = recovery
        if voiceCheck == .checking { voiceCheck = .failed(text) }
        state = .failed; status = "Couldn’t finish"; reply = text; present?()
    }
    public func recover() {
        guard let recovery else { return }
        switch recovery {
        case .permission(let kind): permissions.openSettings(kind)
        case .voiceSettings: settingsSection = "Voice"; openSettings?()
        case .providerSettings: settingsSection = "Intelligence"; openSettings?()
        case .privacySettings: settingsSection = "Privacy"; openSettings?()
        }
    }
    public func refreshEnvironment() {
        let keyboard = permissions.state(.keyboard)
        permissions.refresh(); microphones.refresh()
        discovery.refresh(language: settings.language, permissions: permissions, speechBackend: settings.speechBackend, remoteSpeechConfigured: settings.remoteSpeechConsent && hasSavedKey, modernSpeechReady: modernSpeechReady)
        speechResourceCheck?.cancel()
        let language = settings.language
        speechResourceCheck = Task { [weak self] in
            let status = await AppleSpeechResources.status(locale: language)
            guard !Task.isCancelled, let self, self.settings.language == language else { return }
            self.modernSpeechReady = status == .ready
            self.discovery.refresh(language: language, permissions: self.permissions, speechBackend: self.settings.speechBackend, remoteSpeechConfigured: self.settings.remoteSpeechConsent && self.hasSavedKey, modernSpeechReady: self.modernSpeechReady)
        }
        if !shortcut.available || keyboard != permissions.state(.keyboard) { configureShortcut() }
    }
    private func checkVoicePermissions() {
        guard [.listening, .transcribing].contains(state), recordingReady, activeMicrophone != nil, !voicePermissionsAllowed else { return }
        let kind: PermissionKind = permissions.state(.microphone) != .allowed ? .microphone : .speech
        abortCapture("\(kind.title) access was revoked. Recording was discarded.", recovery: .permission(kind))
    }
    private func checkAudioRoute() {
        guard [.listening, .transcribing].contains(state), let active = activeMicrophone else { return }
        // Keep a working input for this recording even if a preferred device returns.
        // Re-evaluate the preference at the next user activation.
        if microphones.devices.contains(where: { $0.uid == active.uid && $0.deviceID == active.deviceID }) { return }
        adaptMicrophone()
    }
    private func adaptMicrophone() {
        guard state == .listening, wantsListening, !paused,
              let deadline = captureDeadline, ContinuousClock.now < deadline,
              microphoneRecoveries < 2 else {
            abortCapture("No stable microphone is available. Recording stopped; reconnect a microphone and try again.")
            return
        }
        microphoneRecoveries += 1
        let failed = activeMicrophone
        // Refresh without delivering a recursive route-change callback.
        activeMicrophone = nil
        microphones.refresh()
        if let failed {
            let keepPreferred = !settings.microphoneUID.isEmpty &&
                failed.uid == settings.microphoneUID &&
                !retriedPreferredMicrophone &&
                microphones.devices.contains(where: { $0.uid == failed.uid })
            if keepPreferred { retriedPreferredMicrophone = true }
            else { unavailableMicrophones.insert(failed.uid) }
        }
        if (try? microphones.selected(settings.microphoneUID, excluding: unavailableMicrophones)) == nil {
            // A single device may have merely changed format. Allow one clean
            // restart, while the overall recovery and recording limits still apply.
            unavailableMicrophones = []
        }
        guard (try? microphones.selected(settings.microphoneUID, excluding: unavailableMicrophones)) != nil else {
            abortCapture("No microphone is available. Connect an input device and try again.")
            return
        }
        let activation = voiceActivation, purpose = capturePurpose
        sessionID = UUID(); task?.cancel(); recordingLimit?.cancel(); speech.cancel()
        transcript = ""; recordingReady = false; state = .idle
        beginCapture(activation: activation, purpose: purpose, recovering: true)
    }
    private func abortCapture(_ text: String, recovery: RecoveryAction = .voiceSettings) {
        sessionID = UUID(); task?.cancel(); recordingLimit?.cancel(); transcript = ""; wantsListening = false
        fail(text, recovery: recovery)
    }
    public var isBusy: Bool { ![.idle, .completed, .failed, .responded, .awaitingInput].contains(state) }
    public var setupReadiness: SetupReadiness {
        SetupReadiness(providerConnected: providerVerified, remoteConsent: processingAllowed, voiceAllowed: voicePermissionsAllowed, microphoneAvailable: (try? microphones.selected(settings.microphoneUID)) != nil, shortcutReady: shortcutAvailable && permissions.state(.keyboard) == .allowed, nativeActionsAvailable: true)
    }
    public func finishSetup() { guard setupReadiness.ready else { return }; settings.setupCompleted = true; settings.setupDismissed = false; settingsSection = "General" }
    public func skipSetup() { settings.setupDismissed = true; settingsSection = "General" }
    public func selectMicrophone(_ uid: String) {
        settings.microphoneUID = uid
        settings.microphoneName = microphones.devices.first { $0.uid == uid }?.name ?? (uid.isEmpty ? "System default" : settings.microphoneName)
    }
    private func scheduleContextExpiry() {
        contextExpiry?.cancel()
        contextExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled, let self else { return }
            if [.listening, .transcribing, .thinking, .executing].contains(self.state) {
                self.scheduleContextExpiry()
                return
            }
            self.context = []; self.archivedConversations = []; self.transcript = ""; self.reply = ""; self.confirmedSummary = ""
            self.cancel()
        }
    }
    private func cancelAutoDismiss() {
        autoDismiss?.cancel()
        autoDismiss = nil
        autoDismissWindow = nil
    }
    private func scheduleDismiss(duration: TimeInterval = 5) {
        cancelAutoDismiss()
        autoDismissWindow = AutoDismissWindow(startedAt: ProcessInfo.processInfo.systemUptime, duration: duration)
        autoDismiss = Task {
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled {
                autoDismissWindow = nil
                archiveActiveConversation()
                dismiss?()
                state = .idle
            }
        }
    }
    private func record(_ tool: String, _ summary: String, _ success: Bool) async {
        guard settings.historyEnabled else { return }
        do { try await store?.append(Activity(tool: tool, summary: summary, succeeded: success)); await refreshHistory() } catch { self.error = "Could not save history: \(error.localizedDescription)" }
    }
    public func refreshHistory() async {
        do { try await store?.purge(days: settings.retentionDays); activities = try await store?.recent() ?? []; if !settings.firstActionSucceeded && activities.contains(where: \.succeeded) { settings.firstActionSucceeded = true } } catch { self.error = error.localizedDescription }
    }
    public func clearHistory() async { do { try await store?.clear(); activities = []; context = []; archivedConversations = [] } catch { self.error = error.localizedDescription } }
    public func saveKey(_ key: String) { providerConnection.saveKey(key.trimmingCharacters(in: .whitespacesAndNewlines)) }
    public func discoverModels() async {
        if settings.reasoningBackend == .openAI { await providerConnection.verify(model: settings.model) }
        else {
            let endpoint = settings.ollamaEndpoint
            if managesLocalRuntime {
                do { try await localRuntime.ensureRunning(endpoint: endpoint) }
                catch { self.error = error.localizedDescription; return }
            }
            await localProviderConnection.refresh(endpoint: endpoint, model: settings.ollamaModel)
            let supported = localProviderConnection.models.filter(\.supportsTools)
            if settings.reasoningBackend == .ollama, settings.ollamaEndpoint == endpoint, settings.ollamaModel.isEmpty, supported.count == 1 {
                settings.ollamaModel = supported[0].id
            }
        }
    }
    public func cancelProviderVerification() { if settings.reasoningBackend == .openAI { providerConnection.cancelVerification() } else { localProviderConnection.cancel() } }
    public func checkSpotifyConnection() {
        guard spotifyConnection != .checking else { return }
        spotifyConnection = .checking
        spotifyCheckTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tool = try NativeTools.registry().tool("spotify")
                let result = try await tool.execute(arguments: .object(["action": .string("current")]))
                guard !Task.isCancelled else { return }
                spotifyConnection = .connected(result.summary)
                await record("spotify", result.summary, true)
            } catch {
                if !Task.isCancelled { spotifyConnection = .failed(error.localizedDescription) }
            }
        }
    }
    public func cancelSpotifyCheck() { spotifyCheckTask?.cancel(); spotifyCheckTask = nil; spotifyConnection = .unchecked }
    public func setLaunchAtLogin(_ enabled: Bool) { do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchesAtLogin = SMAppService.mainApp.status == .enabled } catch { self.error = error.localizedDescription } }
    public private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    public func setNotifications(_ enabled: Bool) {
        Task { do { settings.notifications = enabled ? try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) : false } catch { self.error = error.localizedDescription } }
    }
    private func notify(_ message: String) {
        let content = UNMutableNotificationContent(); content.title = "Sotto"; content.body = message
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    public func shutdown() {
        speechResourceCheck?.cancel(); speechResourceCheck = nil
        cancel(); cancelSpotifyCheck(); providerConnection.shutdown(); localProviderConnection.cancel(); localRuntime.shutdown(); contextExpiry?.cancel(); shortcut.stop(); microphones.stop()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver); self.activationObserver = nil }
        if let sleptObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleptObserver); self.sleptObserver = nil }
    }
}
/// Captured at activation so a click never displays instructions for a held key.
public enum VoiceActivation: Sendable {
    case button, heldShortcut, handsFreeShortcut, toggleShortcut
    var hint: String {
        switch self {
        case .button: "Click Send when finished · Esc to cancel"
        case .heldShortcut: "Release to send · Esc to cancel"
        case .handsFreeShortcut: "Hands-free · Click Send when finished · Esc to cancel"
        case .toggleShortcut: "Press your shortcut again to send · Esc to cancel"
        }
    }
}

public struct AutoDismissWindow: Equatable, Sendable {
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    public init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime, duration: TimeInterval = 5) {
        self.startedAt = startedAt
        self.duration = duration
    }
    public func progress(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        guard duration > 0 else { return 1 }
        return min(max((uptime - startedAt) / duration, 0), 1)
    }
}
