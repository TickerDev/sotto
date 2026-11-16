import SwiftUI
import SottoProviders

/// Setup and Settings share one selected-provider configuration and connection state.
struct ProviderSettingsControls: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPicker("Provider", selection: $model.settings.reasoningBackend) {
                ForEach(ReasoningBackend.allCases) { backend in Text(backend.name).tag(backend) }
            }.disabled(model.isBusy)
            if model.settings.reasoningBackend == .openAI {
                Text("Use your own OpenAI API key. API billing is separate from a ChatGPT subscription.").font(.callout).foregroundStyle(.secondary)
                ProviderSetupControls(model: model)
                if model.hasSavedKey {
                    Button("Disconnect OpenAI", role: .destructive) { model.cancel(); model.saveKey("") }.disabled(model.credentialSaving || model.isBusy)
                }
                SettingsPicker("Reasoning model", selection: $model.settings.model) {
                    ForEach(["gpt-4.1-mini", "gpt-4.1", "gpt-4.1-nano", "gpt-4o", "gpt-4o-mini"], id: \.self) { Text($0).tag($0) }
                }.disabled(model.isBusy)
                if !model.models.isEmpty { Text("Only models with verified tool support are selectable.").font(.caption).foregroundStyle(.secondary) }
            } else {
                OllamaSettingsControls(model: model)
            }
        }
    }
}

private struct OllamaSettingsControls: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use a model installed in Ollama on this Mac. No API key or Sotto account is needed.").font(.callout).foregroundStyle(.secondary)
            TextField("Local server address", text: $model.settings.ollamaEndpoint)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Ollama server address")
                .onSubmit { Task { await model.discoverModels() } }.disabled(model.isBusy)
            Text("Loopback addresses only. Cloud-backed models are blocked; OpenAI credentials are never sent to Ollama. For strict local operation, also disable cloud features in your Ollama server.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Start & connect") { Task { await model.discoverModels() } }
                    .disabled(model.providerChecking || model.isBusy)
                if model.providerChecking {
                    Button("Cancel connection") { model.cancelProviderVerification() }
                    ProgressView().controlSize(.small)
                }
            }
            Text(model.localProviderConnection.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .accessibilityElement(children: .ignore).accessibilityLabel(model.localProviderConnection.status)
                .accessibilityIdentifier("local-provider-status")
            SettingsPicker("Reasoning model", selection: $model.settings.ollamaModel) {
                Text("Choose an installed model").tag("")
                if !model.settings.ollamaModel.isEmpty && !model.localProviderConnection.models.contains(where: { $0.id == model.settings.ollamaModel }) {
                    Text(model.settings.ollamaModel + " · reconnect to verify").tag(model.settings.ollamaModel)
                }
                ForEach(model.localProviderConnection.models) { info in
                    Text(info.supportsTools ? info.id : info.id + " · unavailable").tag(info.id).disabled(!info.supportsTools)
                }
            }.disabled(model.isBusy || model.providerChecking)
            ForEach(model.localProviderConnection.models.filter { !$0.supportsTools }) { info in
                Text("\(info.id): \(info.unavailableReason ?? "Tool calling is unavailable")").font(.caption).foregroundStyle(.secondary)
            }
            Text("Sotto starts an installed local engine when needed and stops its own process when idle or when Sotto quits. Existing servers are left alone. Model downloads are not automatic.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
