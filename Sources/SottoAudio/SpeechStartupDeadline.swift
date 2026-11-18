import Foundation

/// A structured task group would wait for an uncooperative framework call even
/// after its timeout child wins. Return the winning result without awaiting that
/// call, cancel its task, and invalidate its session synchronously on failure.
/// The backend must still check its session after every framework suspension.
enum SpeechStartupDeadline {
    static func run(timeout: Duration, operation: @escaping @Sendable () async throws -> Void,
                    onAbort: @escaping @Sendable () -> Void) async throws {
        let race = StartupRace(onAbort: onAbort)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard race.install(continuation) else { return }
                let work = Task {
                    do { try Task.checkCancellation(); try await operation(); race.finish(.success(())) }
                    catch { race.finish(.failure(error)) }
                }
                let timer = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    race.finish(.failure(SpeechError.message("On-device speech did not become ready. Try again.")))
                }
                race.install(work: work, timer: timer)
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }
}

private final class StartupRace: @unchecked Sendable {
    private let lock = NSLock()
    private let onAbort: @Sendable () -> Void
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    init(onAbort: @escaping @Sendable () -> Void) { self.onAbort = onAbort }

    func install(_ continuation: CheckedContinuation<Void, Error>) -> Bool {
        let completed: Result<Void, Error>? = lock.withLock {
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let completed { continuation.resume(with: completed); return false }
        return true
    }
    func install(work: Task<Void, Never>, timer: Task<Void, Never>) {
        let finished = lock.withLock {
            guard result == nil else { return true }
            self.work = work; self.timer = timer
            return false
        }
        if finished { work.cancel(); timer.cancel() }
    }
    func finish(_ result: Result<Void, Error>) {
        let pending = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Task<Void, Never>?, Task<Void, Never>?)? in
            guard self.result == nil else { return nil }
            self.result = result
            let pending = (continuation, work, timer)
            continuation = nil; work = nil; timer = nil
            return pending
        }
        guard let pending else { return }
        if case .failure = result { onAbort() }
        pending.1?.cancel(); pending.2?.cancel()
        pending.0?.resume(with: result)
    }
}
