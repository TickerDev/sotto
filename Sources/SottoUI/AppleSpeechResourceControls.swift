import SwiftUI
import SottoAudio

struct AppleSpeechResourceControls: View {
    let locale: String
    @State private var status: AppleSpeechResources.Status = .legacy
    @State private var preparing = false
    @State private var message: String?
    @State private var preparation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch status {
            case .ready: Label("Live on-device transcription is ready", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            case .needsDownload:
                Text("Prepare this language for live on-device transcription. Until then, Sotto uses the existing Apple Speech service.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(preparing ? "Preparing language…" : "Prepare on-device speech") {
                        preparing = true; message = nil
                        preparation = Task {
                            do {
                                try await AppleSpeechResources.prepare(locale: locale)
                                let next = await AppleSpeechResources.status(locale: locale)
                                guard !Task.isCancelled else { return }
                                status = next
                            } catch {
                                guard !Task.isCancelled else { return }
                                message = "Couldn’t prepare this language. Try again, or continue with Apple Speech."
                            }
                            preparing = false
                        }
                    }.disabled(preparing)
                    if preparing { ProgressView().controlSize(.small); Button("Cancel") { preparation?.cancel(); preparing = false } }
                }
            case .unsupported, .legacy: Text("Sotto uses Apple Speech streaming for this Mac and language.").font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: locale) {
            preparation?.cancel(); preparing = false; message = nil
            let next = await AppleSpeechResources.status(locale: locale)
            guard !Task.isCancelled else { return }
            status = next
        }
        .onDisappear { preparation?.cancel() }
    }
}
