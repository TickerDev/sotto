import Foundation
import Observation
import SottoProviders

/// Local discovery never reads or modifies provider credentials.
@MainActor @Observable public final class LocalProviderConnection {
    public private(set) var models: [ModelInfo] = []
    public private(set) var status = "Connect to discover installed local models."
    public private(set) var isChecking = false
    private var operation = UUID()
    private var checking: Task<Void, Never>?
    private let makeProvider: @Sendable (String, String) throws -> any ReasoningProvider
    public init(makeProvider: @escaping @Sendable (String, String) throws -> any ReasoningProvider = { try OllamaProvider(endpoint: $0, model: $1) }) { self.makeProvider = makeProvider }
    public func isVerified(_ model: String) -> Bool { models.contains { $0.id == model && $0.supportsTools } }
    public func select(_ model: String) {
        guard !isChecking else { return }
        if isVerified(model) { status = "Connected · \(model) · local" }
        else if models.isEmpty { status = "Connect to discover installed local models." }
        else { status = "Choose an installed model with tool calling." }
    }
    public func refresh(endpoint: String, model: String) async {
        guard !isChecking else { return }
        operation = UUID(); let id = operation
        isChecking = true; models = []; status = "Connecting to Ollama…"
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            defer { if operation == id { isChecking = false } }
            do {
                let catalog = try await makeProvider(endpoint, model).models()
                try Task.checkCancellation()
                guard operation == id else { return }
                models = catalog
                if catalog.isEmpty { status = "No models installed. Download a tool-capable model in Ollama, then refresh." }
                else if !catalog.contains(where: \.supportsTools) { status = "No installed local model advertises tool calling. Cloud-backed models are unavailable." }
                else { status = isVerified(model) ? "Connected · \(model) · local" : "Choose an installed model with tool calling." }
            } catch is CancellationError {
                if operation == id { status = "Connection cancelled" }
            } catch {
                if operation == id { status = error.localizedDescription }
            }
        }
        checking = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
    public func cancel() {
        operation = UUID(); checking?.cancel(); checking = nil; isChecking = false
        status = "Connection cancelled"
    }
    public func invalidate() { cancel(); models = []; status = "Connect to verify this Ollama address." }
}
