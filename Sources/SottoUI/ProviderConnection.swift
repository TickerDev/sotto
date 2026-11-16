import Foundation
import Observation
import OSLog
import SottoSecurity
import SottoProviders
import SottoTools

/// Owns verification independently of SwiftUI view lifetime. Only the newest operation may update UI.
@MainActor @Observable public final class ProviderConnection {
    public private(set) var status = "Checking saved key…"
    public private(set) var lastSaveSucceeded = false
    public private(set) var hasSavedKey = false
    public private(set) var inspectionFailed = false
    public private(set) var isChecking = false
    public private(set) var isSaving = false
    public private(set) var verified = false
    public private(set) var models: [ModelInfo] = []
    public var canVerify: Bool { (hasSavedKey || inspectionFailed) && !isSaving }
    private let credentials: any CredentialStorage
    private let makeProvider: @Sendable (String, String) -> any ReasoningProvider
    private let logger = Logger(subsystem: "org.sotto.mac", category: "provider-connection")
    private var verification: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var verificationID = UUID()
    private var credentialID = UUID()

    public init(credentials: any CredentialStorage = KeychainCredentials.shared, makeProvider: @escaping @Sendable (String, String) -> any ReasoningProvider = { OpenAIProvider(key: $0, model: $1) }) {
        self.credentials = credentials; self.makeProvider = makeProvider
    }
    public func inspectSavedKey() async {
        let id = credentialID
        let verificationAtStart = verificationID
        do {
            let exists = try await credentials.containsKey()
            guard id == credentialID, verificationAtStart == verificationID, !isSaving, !isChecking, !verified else { return }
            hasSavedKey = exists; inspectionFailed = false
            status = exists ? "API key saved in Keychain" : "Add an OpenAI API key to connect."
        } catch {
            guard id == credentialID, verificationAtStart == verificationID, !isSaving, !isChecking, !verified else { return }
            inspectionFailed = true; status = error.localizedDescription
        }
    }
    func reasoningProvider(key: String, model: String) -> any ReasoningProvider { makeProvider(key, model) }
    public func readKey() async throws -> String? { try await credentials.read() }
    @discardableResult public func saveKey(_ key: String) -> Task<Void, Never> {
        cancelVerification(showStatus: false)
        saving?.cancel(); credentialID = UUID(); let id = credentialID
        isSaving = true; lastSaveSucceeded = false; verified = false; models = []; status = key.isEmpty ? "Disconnecting…" : "Saving key…"
        let write = Task<Void, Never> { [weak self, credentials] in
            do {
                try await credentials.save(key)
                guard let self, self.credentialID == id, !Task.isCancelled else { return }
                self.lastSaveSucceeded = true
                self.hasSavedKey = !key.isEmpty; self.inspectionFailed = false; self.isSaving = false
                self.status = key.isEmpty ? "Not connected" : "API key saved in Keychain"
            } catch {
                guard let self, self.credentialID == id, !Task.isCancelled else { return }
                self.isSaving = false; self.status = error.localizedDescription
            }
        }
        saving = write
        return write
    }
    public func verify(model: String) async {
        guard !isChecking, !isSaving else { return }
        verificationID = UUID(); let id = verificationID
        isChecking = true; verified = false; models = []; status = "Reading the saved key…"
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performVerification(model: model, id: id)
        }
        verification = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
    private func performVerification(model: String, id: UUID) async {
        defer { if verificationID == id { isChecking = false } }
        do {
            logger.notice("Verification started; reading Keychain on background worker")
            guard let key = try await credentials.read(), !key.isEmpty else {
                if verificationID == id { hasSavedKey = false }
                throw ToolError.denied("No saved API key. Add one before verifying.")
            }
            try Task.checkCancellation()
            guard verificationID == id else { return }
            status = "Connecting to OpenAI…"
            logger.notice("Requesting model catalog")
            let catalog = try await makeProvider(key, model).models()
            try Task.checkCancellation()
            guard verificationID == id else { return }
            guard catalog.contains(where: { $0.id == model && $0.supportsTools }) else {
                throw ToolError.unavailable("The selected model is not available with tool support. Choose another model and verify again.")
            }
            models = catalog; hasSavedKey = true; inspectionFailed = false; verified = true
            status = "Connected · \(model)"
            logger.notice("Verification completed successfully")
        } catch is CancellationError {
            if verificationID == id { status = "Verification cancelled" }
        } catch {
            guard verificationID == id else { return }
            verified = false; status = error.localizedDescription
            logger.notice("Verification failed; error is displayed in Settings")
        }
    }
    public func cancelVerification(showStatus: Bool = true) {
        let wasChecking = isChecking
        verificationID = UUID(); verification?.cancel(); verification = nil
        isChecking = false; verified = false
        if showStatus && wasChecking { status = "Verification cancelled" }
    }
    public func invalidate() { cancelVerification(showStatus: false); models = []; if !isSaving { status = "Verify the selected model to connect." } }
    public func shutdown() { cancelVerification(showStatus: false); saving?.cancel(); credentialID = UUID(); isSaving = false }
}
