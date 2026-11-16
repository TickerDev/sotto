import SwiftUI
import AppKit
import SottoAudio
import SottoProviders

struct PermissionRow: View {
    @Bindable var center: PermissionCenter
    let kind: PermissionKind
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title).fontWeight(.medium)
                Spacer()
                Text(center.state(kind).label).font(.caption).foregroundStyle(center.state(kind) == .allowed ? .primary : .secondary)
            }
            Text(kind.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if center.state(kind).canRequest && kind != .automation {
                    Button("Allow \(kind.title)") { Task { await center.request(kind) } }
                        .disabled(center.requesting != nil)
                } else {
                    Button("Open \(kind.title) Settings…") { center.openSettings(kind) }
                }
                if center.requesting == kind { ProgressView().controlSize(.small) }
            }
            if kind == .keyboard && center.state(kind) == .unavailable {
                Text("macOS is not granting keyboard access to this running copy. If Sotto is already enabled in System Settings, restart Sotto. If it still cannot connect, remove the old Sotto entry from Input Monitoring and add this copy again.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let restart = center.restartApplication { Button("Restart Sotto", action: restart) }
                    Button("Show this copy in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                }
            }
        }.accessibilityElement(children: .contain)
    }
}

struct MicrophonePicker: View {
    @Bindable var model: AppModel
    private var missing: Bool {
        !model.settings.microphoneUID.isEmpty && !model.microphones.devices.contains { $0.uid == model.settings.microphoneUID }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsPicker("Preferred microphone", selection: Binding(get: { model.settings.microphoneUID }, set: { model.selectMicrophone($0) })) {
                Text("Automatic — Recommended").tag("")
                if missing { Text(model.settings.microphoneUID == Microphones.legacySelection ? "Automatic (previous microphone unavailable)" : "\(model.settings.microphoneName) · unavailable").tag(model.settings.microphoneUID) }
                ForEach(model.microphones.devices) { Text($0.name).tag($0.uid) }
            }
            if let active = model.activeMicrophone {
                Text("Using \(active.name)").font(.caption).foregroundStyle(.secondary)
            } else if let device = try? model.microphones.selected(model.settings.microphoneUID) {
                Text("Ready to use \(device.name)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Sotto prefers your choice when available, then uses the system microphone or another available input. If the source changes while recording, Sotto starts a fresh recording and asks you to repeat.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Refresh microphones") { model.microphones.refresh() }
            if !model.microphones.monitoringAvailable { Text("Automatic device monitoring is unavailable. Refresh inputs before recording.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ProviderSetupControls: View {
    @Bindable var model: AppModel
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasSavedKey { Label("API key saved in Keychain", systemImage: "key").font(.caption).foregroundStyle(.secondary) }
            SecureField(model.hasSavedKey ? "Replace API key" : "OpenAI API key", text: $key)
                .textFieldStyle(.roundedBorder).onSubmit { save() }
            HStack {
                Button("Save to Keychain") { save() }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.credentialSaving)
                Button("Verify connection") { Task { await model.discoverModels() } }
                    .disabled(!model.canVerifyProvider || model.providerChecking)
                if model.providerChecking { Button("Cancel verification") { model.cancelProviderVerification() }; ProgressView().controlSize(.small) }
            }
            Text(model.credentialStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .accessibilityElement(children: .ignore).accessibilityLabel(model.credentialStatus).accessibilityIdentifier("provider-connection-status")
        }
    }
    private func save() { guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; model.saveKey(key); key = "" }
}

struct SetupView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Just say it. It’s done.").font(.system(size: 24, weight: .semibold))
                Text("Start with something simple. Sotto can open your folders and find files without an AI connection.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup("Try your first request") {
                Button("Open my Downloads folder") { model.submit("Open my Downloads folder") }
                    .buttonStyle(.borderedProminent).disabled(model.isBusy || model.paused)
                Button("Find my latest PDF") { model.submit("Find my latest PDF") }.disabled(model.isBusy || model.paused)
                Button("Find my résumé") { model.submit("Find my resume") }.disabled(model.isBusy || model.paused)
                Button("What’s on my calendar today?") { model.submit("What’s on my calendar today?") }.disabled(model.isBusy || model.paused)
                Text("These requests stay on your Mac. Calendar asks for permission the first time; file search uses Spotlight’s index.").font(.caption).foregroundStyle(.secondary)
                if model.settings.firstActionSucceeded { Label("Your first action is complete", systemImage: "checkmark.circle") }
            }
            SettingsGroup("Say it aloud") {
                Text("Use the menu bar or your shortcut. Sotto asks only for the voice permissions it needs when you start listening.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Start listening") { model.activate() }.disabled(model.isBusy || model.paused)
                ShortcutSettingsRow(model: model)
                Text("Keyboard access is optional. You can always use the menu bar.").font(.caption).foregroundStyle(.secondary)
            }
            SettingsGroup("More help, when you need it") {
                Label(OnDeviceIntelligence.status, systemImage: "sparkles")
                Text("On supported Macs, Sotto uses on-device intelligence for more flexible requests. Otherwise, basic commands still work. Other requests need an intelligence connection.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Explore Intelligence…") { model.settingsSection = "Intelligence" }
            }
            HStack {
                Button("Explore on my own") { model.skipSetup() }
                Spacer()
                Button("Start using Sotto") { model.finishSetup() }
            }
        }.onAppear { model.refreshEnvironment() }
    }
}

struct PermissionSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsGroup("Voice & keyboard") {
                ForEach([PermissionKind.microphone, .speech, .keyboard]) { PermissionRow(center: model.permissions, kind: $0) }
                Button("Refresh permission status") { model.refreshEnvironment() }
            }
            SettingsGroup("Native integrations") {
                PermissionRow(center: model.permissions, kind: .reminders)
                PermissionRow(center: model.permissions, kind: .calendar)
                PermissionRow(center: model.permissions, kind: .automation)
                Text("Spotify consent is managed per target app. Sotto does not infer that permission has been granted. File access follows macOS authorization; Full Disk Access is not requested.").font(.caption).foregroundStyle(.secondary)
            }
            SettingsGroup("Not requested") {
                Text("Accessibility automation and screen capture are not implemented or enabled. Sotto does not ask for those permissions.").foregroundStyle(.secondary)
            }
        }.onAppear { model.refreshEnvironment() }
    }
}
