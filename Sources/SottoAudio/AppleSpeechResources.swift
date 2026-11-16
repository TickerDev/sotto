@preconcurrency import Speech
import Foundation

public enum AppleSpeechResources {
    public enum Status: Sendable { case ready, needsDownload, unsupported, legacy }
    public static func status(locale: String) async -> Status {
        if #available(macOS 26, *) {
            guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else { return .unsupported }
            let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            return await AssetInventory.status(forModules: [module]) == .installed ? .ready : .needsDownload
        }
        return .legacy
    }
    public static func prepare(locale: String) async throws {
        guard #available(macOS 26, *), SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else { throw SpeechError.onDeviceUnavailable }
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await withTaskCancellationHandler { try await request.downloadAndInstall() } onCancel: { request.progress.cancel() }
        }
        try Task.checkCancellation()
    }
}
