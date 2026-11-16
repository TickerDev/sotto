import Foundation
import Observation
import SottoProviders
import SottoTools

@MainActor protocol LocalRuntimeProcess: AnyObject {
    var running: Bool { get }
    func launch(executable: URL, environment: [String: String]) throws
    func stop()
}
@MainActor final class OllamaChildProcess: LocalRuntimeProcess {
    private let process = Process()
    var running: Bool { process.isRunning }
    func launch(executable: URL, environment: [String: String]) throws {
        process.executableURL = executable; process.arguments = ["serve"]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
    func stop() { if process.isRunning { process.terminate() } }
}

/// Owns only the child it launched. Never changes launch agents or kills another server.
@MainActor @Observable public final class ManagedOllamaRuntime {
    public private(set) var status = "Local intelligence starts when needed."
    public private(set) var starting = false
    public var isInstalled: Bool { executable() != nil }
    public var ownsRunningProcess: Bool { child?.running == true }
    private var child: (any LocalRuntimeProcess)?
    private var launch: Task<Void, Error>?
    private var launchEndpoint: URL?
    private var idle: Task<Void, Never>?
    private var generation = UUID()
    private var users = 0
    private let executable: @MainActor () -> URL?
    private let makeProcess: @MainActor () -> any LocalRuntimeProcess
    private let probe: @Sendable (String) async -> Bool
    private let pause: @Sendable () async throws -> Void
    private let attempts: Int
    private let idleDuration: Duration
    public convenience init() {
        self.init(executable: Self.installedExecutable, makeProcess: { OllamaChildProcess() }, probe: Self.probe)
    }
    init(executable: @escaping @MainActor () -> URL?, makeProcess: @escaping @MainActor () -> any LocalRuntimeProcess, probe: @escaping @Sendable (String) async -> Bool, attempts: Int = 40, idleDuration: Duration = .seconds(300), pause: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }) {
        self.executable = executable; self.makeProcess = makeProcess; self.probe = probe
        self.attempts = attempts; self.idleDuration = idleDuration; self.pause = pause
    }
    public static func installedExecutable() -> URL? {
        // Do not search the shell PATH or execute a workspace-supplied program.
        ["/Applications/Ollama.app/Contents/Resources/ollama", NSHomeDirectory() + "/Applications/Ollama.app/Contents/Resources/ollama", "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
    nonisolated public static func probe(_ endpoint: String) async -> Bool {
        guard let endpoint = try? OllamaEndpoint(endpoint) else { return false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.5; configuration.timeoutIntervalForResource = 1
        configuration.connectionProxyDictionary = [:]; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: RuntimeNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: endpoint.url.appendingPathComponent("api/version"))
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return false }
            var data = Data()
            for try await byte in bytes { guard data.count < 4096 else { return false }; data.append(byte) }
            return (try? JSONDecoder().decode(JSONValue.self, from: data).object?["version"]?.string) != nil
        } catch { return false }
    }
    public func ensureRunning(endpoint: String) async throws {
        let requestedEndpoint = try OllamaEndpoint(endpoint).url
        idle?.cancel()
        if let launch {
            guard launchEndpoint == requestedEndpoint else { throw ToolError.unavailable("Another local connection is starting. Try again in a moment.") }
            try await launch.value
            try Task.checkCancellation()
            return
        }
        launchEndpoint = requestedEndpoint
        let id = generation
        starting = true; status = "Preparing local intelligence…"
        let task = Task { [self] in
            defer { if generation == id { starting = false; launch = nil; launchEndpoint = nil; scheduleIdle() } }
            do {
                if await probe(endpoint) {
                    try Task.checkCancellation()
                    guard generation == id else { throw CancellationError() }
                    status = "Ready on this Mac"; return
                }
                try Task.checkCancellation()
                guard generation == id else { throw CancellationError() }
                let normalized = try OllamaEndpoint(endpoint).url
                guard normalized.scheme == "http", normalized.host == "127.0.0.1", (normalized.port ?? 80) == 11434 else {
                    throw ToolError.unavailable("This custom local connection is unavailable. Sotto manages the standard local connection; review the custom address in Advanced.")
                }
                guard let binary = executable() else { throw ToolError.unavailable("Install the Ollama app to enable local intelligence. Sotto will start it for you after installation.") }
                if child?.running != true {
                    let process = makeProcess()
                    try process.launch(executable: binary, environment: [
                        "HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                        "TMPDIR": NSTemporaryDirectory(), "OLLAMA_HOST": "127.0.0.1:11434",
                        "OLLAMA_NO_CLOUD": "1", "OLLAMA_KEEP_ALIVE": "1m"
                    ])
                    child = process
                }
                for _ in 0..<attempts {
                    try Task.checkCancellation()
                    guard generation == id else { throw CancellationError() }
                    if await probe(endpoint) {
                        try Task.checkCancellation()
                        guard generation == id else { throw CancellationError() }
                        // If our child lost a bind race, release the exited process
                        // and reuse the already-running server without owning it.
                        if child?.running == false { child = nil }
                        status = "Ready on this Mac"; return
                    }
                    guard child?.running == true else { throw ToolError.unavailable("Local intelligence stopped while starting. Try Enable local intelligence again.") }
                    try await pause()
                }
                throw ToolError.unavailable("Local intelligence did not become ready. Try again, or review diagnostics in Advanced.")
            } catch {
                if generation == id {
                    child?.stop(); child = nil
                    status = error is CancellationError ? "Local setup cancelled" : error.localizedDescription
                }
                throw error
            }
        }
        launch = task
        try await withTaskCancellationHandler { try await task.value } onCancel: {
            task.cancel()
        }
    }
    public func beginUse() { users += 1; idle?.cancel() }
    public func endUse() { users = max(0, users - 1); scheduleIdle() }
    private func scheduleIdle() {
        idle?.cancel()
        guard users == 0, ownsRunningProcess else { return }
        let id = generation
        idle = Task { [weak self, idleDuration] in
            try? await Task.sleep(for: idleDuration)
            guard !Task.isCancelled, let self, generation == id, users == 0 else { return }
            child?.stop(); child = nil; status = "Local intelligence will start when needed."
        }
    }
    public func shutdown() {
        generation = UUID(); launch?.cancel(); launch = nil; launchEndpoint = nil; idle?.cancel(); idle = nil
        child?.stop(); child = nil; starting = false
        status = "Local intelligence will start when needed."
    }
}
private final class RuntimeNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
