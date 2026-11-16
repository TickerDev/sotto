import Foundation
import Darwin
import SottoTools

/// Internal transport for reviewed, fixed AppleScript only. Never exposed as an agent tool.
struct AppleScriptExecutor: Sendable {
    func execute(_ source: String, timeout: TimeInterval = 30, didStart: (@Sendable () -> Void)? = nil) async throws -> String {
        let operation = ScriptOperation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { operation.start(source, timeout: timeout, didStart: didStart, continuation: $0) }
        } onCancel: { operation.cancel() }
    }
}

/// Every mutable field belongs to the serial queue. Callbacks only enqueue immutable data.
private final class ScriptOperation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.sotto.mac.apple-events", qos: .userInitiated)
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var output = Data()
    private var errors = Data()
    private var outputEnded = false
    private var errorsEnded = false
    private var exitStatus: Int32?
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private var cancelled = false
    private let limit = 65_536

    func start(_ source: String, timeout: TimeInterval, didStart: (@Sendable () -> Void)?, continuation: CheckedContinuation<String, Error>) {
        queue.async { [self] in
            self.continuation = continuation
            if self.cancelled { self.finish(.failure(CancellationError())); return }
            let process = Process(); let out = Pipe(); let err = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardInput = FileHandle.nullDevice; process.standardOutput = out; process.standardError = err
            self.process = process; self.outputPipe = out; self.errorPipe = err
            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData; if data.isEmpty { handle.readabilityHandler = nil }; self.receive(data, isError: false)
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData; if data.isEmpty { handle.readabilityHandler = nil }; self.receive(data, isError: true)
            }
            process.terminationHandler = { child in
                let status = child.terminationStatus
                self.queue.async { self.exitStatus = status; self.completeIfReady() }
            }
            do {
                try process.run()
                try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
                didStart?()
                self.queue.asyncAfter(deadline: .now() + max(0.01, timeout)) { [weak self] in
                    guard let self, self.exitStatus == nil, !self.finished else { return }
                    self.abort(ToolError.unavailable("Apple Events timed out. Spotify may already have received the command; check playback before retrying."))
                }
            } catch {
                self.finish(.failure(ToolError.unavailable("Could not start the native Apple Events helper: \(error.localizedDescription)")))
                self.cleanup()
            }
        }
    }
    func cancel() {
        queue.async {
            self.cancelled = true
            if self.continuation != nil { self.abort(CancellationError()) }
        }
    }
    private func receive(_ data: Data, isError: Bool) {
        queue.async {
            if data.isEmpty {
                if isError { self.errorsEnded = true; self.errorPipe?.fileHandleForReading.readabilityHandler = nil }
                else { self.outputEnded = true; self.outputPipe?.fileHandleForReading.readabilityHandler = nil }
            } else if !self.finished {
                if (isError ? self.errors.count : self.output.count) + data.count > self.limit {
                    self.abort(ToolError.unavailable("Apple Events returned too much data"))
                } else if isError { self.errors.append(data) } else { self.output.append(data) }
            }
            self.completeIfReady()
        }
    }
    private func abort(_ error: Error) {
        guard !finished else { return }
        finish(.failure(error))
        guard let process, process.isRunning else { return }
        process.terminate()
        queue.asyncAfter(deadline: .now() + 0.3) {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
    }
    private func completeIfReady() {
        guard let exitStatus, outputEnded, errorsEnded else { return }
        if !finished {
            if exitStatus == 0 {
                finish(.success(String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                let message = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let denied = message.contains("-1743") || message.contains("not authorized")
                finish(.failure(denied ? ToolError.denied("Allow Sotto to control Spotify in System Settings → Privacy & Security → Automation.") : ToolError.unavailable("Spotify Automation failed: \(message.isEmpty ? "helper exited with status \(exitStatus)" : message)")))
            }
        }
        cleanup()
    }
    private func finish(_ result: Result<String, Error>) {
        guard !finished, let continuation else { return }
        finished = true; self.continuation = nil; continuation.resume(with: result)
    }
    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil; errorPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil; process = nil; outputPipe = nil; errorPipe = nil
    }
}
