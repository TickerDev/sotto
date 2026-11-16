import SwiftUI

struct RealtimeSpeechSettings: View {
    @Bindable var model: AppModel
    @State private var apiKey = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live transcription from OpenAI. Your command model stays the same.").font(.callout)
            SettingsToggle("Allow audio to OpenAI", isOn: $model.settings.remoteSpeechConsent)
            Text("Microphone audio is streamed to OpenAI only while you explicitly listen. API billing and OpenAI’s data policies apply; a ChatGPT subscription doesn’t include API access. Sotto never saves recordings or switches speech services automatically.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.hasSavedKey {
                Label("Uses your saved OpenAI API key", systemImage: "key").font(.caption).foregroundStyle(.secondary)
            }
            SecureField(model.hasSavedKey ? "Replace API key" : "OpenAI API key", text: $apiKey).textFieldStyle(.roundedBorder)
            Button("Save to Keychain") { model.saveKey(apiKey); apiKey = "" }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.credentialSaving)
            Text(model.credentialStatus).font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Details") {
                LabeledContent("Transcription model", value: "gpt-live-transcribe")
                Text("The shortcut release or Send button ends the audio turn. Only the final transcript is passed to the agent. Escape discards the request and closes the connection; audio already sent cannot be recalled.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(.caption)
        }
    }
}
