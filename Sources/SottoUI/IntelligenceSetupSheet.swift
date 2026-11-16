import SwiftUI
import SottoProviders

struct IntelligenceSetupSheet: View {
    @Bindable var model: AppModel
    @State private var key = ""
    @State private var allowRemote = false
    @State private var showAPI = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Enable more help", systemImage: "sparkles").font(.title2.weight(.semibold))
            Text(model.pendingIntelligence.intent == nil
                 ? "Choose how Sotto handles requests that need intelligence. Basic commands already work on this Mac."
                 : "This request needs intelligence. Your words will stay on this Mac while you connect, then Sotto will continue your request.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("On-device intelligence", value: OnDeviceIntelligence.status)
                if OnDeviceIntelligence.available {
                    Button("Use on-device intelligence") { model.useAvailableIntelligence() }
                }
                LabeledContent("Local intelligence", value: model.localProviderConnection.models.contains(where: \.supportsTools) ? "Ready on this Mac" : "No compatible local model found")
                Text(model.localRuntime.status).font(.caption).foregroundStyle(.secondary)
                Button("Enable local intelligence") { model.enableLocalIntelligence() }.disabled(model.intelligenceConnecting)
                Text("Sotto starts the local engine for you and uses a compatible installed model. No terminal commands or account are needed.").font(.caption).foregroundStyle(.secondary)
                if !model.localRuntime.isInstalled {
                    Link("Install Ollama app…", destination: URL(string: "https://ollama.com/download/mac")!)
                }
                Button("Check this Mac again") { model.checkIntelligenceForSetup() }.disabled(model.intelligenceConnecting)
                if model.localProviderConnection.models.contains(where: \.supportsTools) {
                    Button("Use local intelligence") { model.useAvailableIntelligence() }
                }
            }.font(.callout)
            DisclosureGroup("Connect OpenAI API", isExpanded: $showAPI) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Requires an OpenAI API account with billing enabled. A ChatGPT subscription does not include API usage. Usage charges may apply.")
                    SecureField(model.hasSavedKey ? "API key (leave empty to use saved key)" : "API key", text: $key).textFieldStyle(.roundedBorder)
                    Toggle("Allow this request and future requests to use OpenAI", isOn: $allowRemote)
                    Text("Your words, conversation context and tool results may be sent directly to OpenAI. Results may include filenames and reminder titles. Audio stays separate. You can revoke this in Privacy.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(model.pendingIntelligence.intent == nil ? "Verify and enable OpenAI" : "Verify and continue my request") {
                        model.connectIntelligence(key: key, remoteConsent: allowRemote)
                        key = ""
                    }.disabled(!allowRemote || (!model.hasSavedKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || model.intelligenceConnecting)
                }.padding(.top, 12)
            }
            if model.intelligenceConnecting { ProgressView("Checking connection…").controlSize(.small) }
            if let message = model.intelligenceSetupMessage {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("intelligence-setup-status")
            }
            HStack {
                Button("Cancel", role: .cancel) { model.cancelIntelligenceSetup() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Advanced…") { model.cancelIntelligenceSetup(); model.settingsSection = "Intelligence" }
            }
        }
        .padding(28).frame(width: 480)
        .interactiveDismissDisabled()
    }
}
