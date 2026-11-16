import SwiftUI
import AppKit
import AVFoundation
import Speech
import EventKit
import SottoAudio
import SottoTools
import SottoProviders

public struct SettingsView: View {
    @Bindable var model: AppModel
    private var section: String { model.settingsSection }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let sections = [("Setup", "wand.and.stars"), ("General", "switch.2"), ("Intelligence", "sparkles"), ("Voice", "waveform"), ("Integrations", "square.stack.3d.up"), ("Permissions", "hand.raised"), ("Privacy", "lock.shield"), ("Activity", "clock"), ("About", "info.circle")]
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 20, weight: .medium)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sotto").font(.system(size: 20, weight: .semibold))
                        Text("Just say it. It’s done.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 18)
                List(selection: $model.settingsSection) {
                    ForEach(sections, id: \.0) { title, icon in
                        Label { Text(title).font(.system(size: 13, weight: model.settingsSection == title ? .medium : .regular)) } icon: {
                            Image(systemName: icon).font(.system(size: 15, weight: .regular)).foregroundStyle(.secondary).frame(width: 22)
                        }
                        .tag(title).padding(.vertical, 5)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
                else { NativeMaterial(material: .sidebar, blending: .behindWindow) }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(section).font(.system(size: 23, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
                .background {
                    if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
                    else { Color.clear }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        switch section {
                        case "Setup": SetupView(model: model)
                        case "General": general
                        case "Intelligence": providers
                        case "Voice": voice
                        case "Integrations": integrations
                        case "Permissions": permissions
                        case "Privacy": privacy
                        case "Activity": activity
                        default: about
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .controlSize(.regular)
                .pickerStyle(.menu)
                .toggleStyle(.switch)
            }
            .background {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
                else { NativeMaterial(material: .underWindowBackground, blending: .behindWindow) }
            }
        }
        .frame(minWidth: 780, minHeight: 580)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() }
            else { NativeMaterial(material: .underWindowBackground, blending: .behindWindow).ignoresSafeArea() }
        }
        .background(SettingsWindowChrome())
        .onAppear { model.refreshEnvironment() }
        .sheet(isPresented: $model.intelligenceSetupPresented) { IntelligenceSetupSheet(model: model) }
        .sheet(item: $model.integrationRequest) { request in IntegrationAccessSheet(model: model, request: request) }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .labeledContentStyle(SettingsValueStyle())
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.settingsSection)
        .alert("Sotto", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var general: some View {
        Group {
            SettingsGroup("At your fingertips") {
                SettingsToggle("Launch at login", isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) }))
                ShortcutSettingsRow(model: model)
                SettingsPicker("Shortcut behavior", selection: $model.settings.toggleToTalk) {
                    Text("Hold to talk").tag(false)
                    Text("Press to toggle").tag(true)
                }.disabled(model.isBusy)
                LabeledContent("Global shortcut", value: model.shortcutStatus)
                Button("Enable keyboard access…") { Task { await model.permissions.request(.keyboard); model.configureShortcut() } }
                Button("Retry shortcut registration") { model.configureShortcut() }
            }
            SettingsGroup("Presentation") {
                SettingsPicker("Appearance", selection: $model.settings.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                SettingsToggle("Completion notifications", isOn: Binding(get: { model.settings.notifications }, set: { model.setNotifications($0) }))
                SettingsToggle("Pause Sotto", isOn: $model.paused).onChange(of: model.paused) { _, paused in if paused { model.cancel() } }
            }
        }
    }
    private var providers: some View {
        Group {
            SettingsGroup("Automatic — Recommended") {
                SettingsToggle("Choose intelligence automatically", isOn: $model.settings.automaticIntelligence)
                    .disabled(model.isBusy)
                Text("Basic commands use your Mac directly. Other requests prefer Apple’s on-device intelligence, then an available local model. Automatic never switches to a paid connection.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            SettingsGroup("Connected intelligence") {
                Button("Enable intelligence…") { model.showIntelligenceSetup() }.disabled(model.isBusy)
                LabeledContent("On-device intelligence", value: OnDeviceIntelligence.status)
                LabeledContent("Local models", value: model.localProviderConnection.models.contains(where: { $0.supportsTools }) ? "Ready on this Mac" : "Additional setup required")
                LabeledContent("OpenAI API", value: model.providerConnection.verified ? "Connection verified" : model.hasSavedKey ? "Verify connection in Advanced" : "Additional setup required")
                Text("ChatGPT subscription sign-in is not supported in this build. OpenAI API use has separate billing and requires your permission in Privacy.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Check this Mac again") {
                    model.refreshEnvironment()
                    Task { await model.localProviderConnection.refresh(endpoint: model.settings.ollamaEndpoint, model: model.settings.ollamaModel) }
                }
            }
            SettingsGroup("Advanced") {
                DisclosureGroup("Providers, models & diagnostics") {
                    ProviderSettingsControls(model: model).padding(.top, 12)
                    Text("To use your selected provider, turn off Automatic. Sotto manages the installed local engine when needed. Model downloads require separate setup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var voice: some View {
        Group {
            SettingsGroup("Input") {
                MicrophonePicker(model: model)
                SettingsPicker("Transcription", selection: $model.settings.speechBackend) {
                    ForEach(SpeechBackend.allCases) { Text($0.name).tag($0) }
                }.disabled(model.isBusy)
                SettingsPicker("Language", selection: $model.settings.language) { ForEach(["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "he-IL"], id: \.self) { Text(Locale.current.localizedString(forIdentifier: $0) ?? $0).tag($0) } }
                if model.settings.speechBackend == .apple {
                    AppleSpeechResourceControls(locale: model.settings.language)
                    SettingsToggle("Require on-device recognition", isOn: $model.settings.onDeviceSpeech)
                    Text("When disabled, Apple may process audio remotely. Some languages need downloaded speech assets. Audio is captured only while you explicitly listen and is never saved by Sotto.").font(.caption).foregroundStyle(.secondary)
                } else { RealtimeSpeechSettings(model: model) }
                SettingsToggle("Audio feedback", isOn: $model.settings.audioFeedback)
                SettingsToggle("Prepare commands during pauses", isOn: $model.settings.prepareWhileSpeaking)
                Text("Sotto can start reasoning on stable words while you pause. Actions wait until you finish and your transcript is confirmed. With a remote command model, these words may be sent to it under your reasoning permission.").font(.caption).foregroundStyle(.secondary)
            }
            SettingsGroup("Microphone check") {
                Button("Test transcription only") { model.beginListening(purpose: .voiceCheck) }.disabled(model.isBusy || model.paused)
                Text(model.settings.speechBackend == .apple ? "Uses Apple Speech without calling your command model or taking an action. Click Finish in the capsule when done." : "Uses OpenAI Realtime and sends microphone audio to OpenAI with your permission. Your command model is not called and no action runs. Click Finish when done.").font(.caption).foregroundStyle(.secondary)
            }
            SettingsGroup("Try it") { Button(model.state == .listening ? "Send recording" : "Start listening") { model.activate() }; Text("Click Start listening, speak, then click Send in the capsule. You can also activate Sotto from the menu bar.").font(.caption).foregroundStyle(.secondary) }
            if !model.voiceTimings.isEmpty {
                SettingsGroup("Advanced") {
                    DisclosureGroup("Last voice interaction timing") {
                        ForEach(model.voiceTimings.keys.sorted(), id: \.self) { key in
                            LabeledContent(VoiceTimingLabels.title(key), value: String(format: "%.1f ms", model.voiceTimings[key] ?? 0)).font(.caption)
                        }
                        Text("Local measurements only. Input-end timing starts when you release or press Send; it is not an acoustic word-end measurement.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private var integrations: some View {
        Group {
            SettingsGroup("Spotify connection") {
                Text("Check the current track through the native adapter without sending anything to OpenAI or changing playback.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(model.spotifyConnection == .checking ? "Checking…" : "Check current track") { model.checkSpotifyConnection() }.disabled(model.spotifyConnection == .checking)
                    if model.spotifyConnection == .checking { ProgressView().controlSize(.small); Button("Cancel check") { model.cancelSpotifyCheck() } }
                }
                switch model.spotifyConnection {
                case .unchecked: EmptyView()
                case .checking: Text("Waiting for Spotify. Your interface remains available.").font(.caption).foregroundStyle(.secondary)
                case .connected(let result): Label(result, systemImage: "checkmark.circle").font(.caption).textSelection(.enabled)
                case .failed(let message): Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Button("Open Automation Settings…") { model.permissions.openSettings(.automation) }
            }
            SettingsGroup("On this Mac") {
                ForEach(model.discovery.snapshot?.capabilities ?? []) { capability in
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(capability.title, value: capability.state == .ready ? "Ready" : capability.state == .permissionRequired ? "Permission needed" : capability.state == .setupRequired ? "Setup needed" : "Unavailable")
                        Text(capability.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Refresh available capabilities") { model.refreshEnvironment() }
            }
            SettingsGroup("Advanced") {
                DisclosureGroup("Tool information") {
                    ForEach(NativeToolsForUI.descriptors, id: \.id) { tool in
                        LabeledContent(tool.description, value: tool.id).font(.caption)
                    }
                    Text("Community packages and MCP connections are not supported in this build.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var permissions: some View { PermissionSettingsView(model: model) }
    private var privacy: some View {
        Group {
            SettingsGroup("Your Mac, your choice") {
                LabeledContent("Selected provider", value: model.settings.reasoningBackend.name)
                SettingsToggle("Allow requests to OpenAI", isOn: $model.settings.remoteConsent)
                Text("Transcripts, follow-up context, tool schemas, and tool results (including filenames and reminder titles) are sent directly to OpenAI when enabled. Sotto requests store:false; provider retention policies still apply. No Sotto server or account is involved. Screenshots and raw microphone audio are never sent to the reasoning provider.").font(.callout).foregroundStyle(.secondary)
                Text("This choice controls command reasoning. Transcription is separate: Voice settings can allow microphone audio to OpenAI Realtime even with local command reasoning. Apple Speech stays on-device when required. Ollama receives reasoning requests at its configured loopback address and rejects advertised cloud-backed models.").font(.caption).foregroundStyle(.secondary)
            }
            SettingsGroup("On this Mac") {
                SettingsToggle("Keep local activity history", isOn: $model.settings.historyEnabled)
                SettingsPicker("Retention", selection: $model.settings.retentionDays) { Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90) }.onChange(of: model.settings.retentionDays) { Task { await model.refreshHistory() } }
                Text("History contains actual tool results and errors. Transcripts are kept only in memory for up to five minutes of follow-up use. Turning history off stops new writes; delete existing history below.").font(.caption).foregroundStyle(.secondary)
                Button("Delete all history & conversation", role: .destructive) { Task { await model.clearHistory() } }
            }
        }
    }
    private var activity: some View {
        SettingsGroup("Actual tool activity") {
            if model.activities.isEmpty { ContentUnavailableView("No activity yet", systemImage: "clock", description: Text("Confirmed actions and tool errors appear here.")) }
            ForEach(model.activities) { item in HStack(alignment: .top) { Image(systemName: item.succeeded ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(item.succeeded ? Color.green : Color.orange); VStack(alignment: .leading, spacing: 4) { Text(item.summary); Text("\(item.tool) · \(item.date.formatted())").font(.caption).foregroundStyle(.secondary) } } }
        }
    }
    private var about: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 12) { Image(systemName: "waveform.circle.fill").font(.system(size: 48)).foregroundStyle(Color.accentColor); Text("Sotto").font(.largeTitle.weight(.semibold)); Text("Just say it. It’s done.").foregroundStyle(.secondary); Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · macOS 14+").font(.caption) }.padding(.vertical, 16)
            Text("Open source · Apache 2.0 license. GRDB.swift is distributed under MIT. No automatic updater is installed.")
            Text("A public GitHub repository has not been configured for this local project.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
import SottoIntegrations
private enum NativeToolsForUI { static var descriptors: [ToolDescriptor] { NativeTools.registry().descriptors } }
