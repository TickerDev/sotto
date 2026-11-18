import Foundation
import SottoTools

enum TimerDelivery: String, Codable, Sendable {
    case needsScheduling, scheduled, quiet, disabled, failed, elapsedUnverified, cancellationPending
}
struct SottoTimer: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let deadline: Date
    var delivery: TimerDelivery
    init(id: String, name: String, deadline: Date, delivery: TimerDelivery = .needsScheduling) {
        self.id = id; self.name = name; self.deadline = deadline; self.delivery = delivery
    }
    private enum CodingKeys: String, CodingKey { case id, name, deadline, delivery }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        deadline = try values.decode(Date.self, forKey: .deadline)
        delivery = try values.decodeIfPresent(TimerDelivery.self, forKey: .delivery) ?? .needsScheduling
    }
}

/// Wall-clock deadlines persist before dispatch. Cancellation tombstones prevent
/// a late scheduling completion or relaunch from resurrecting a cancelled timer.
actor TimerEngine {
    static let shared = TimerEngine()
    private let file: URL
    private let notifications: any TimerNotifications
    private let now: @Sendable () -> Date
    private var timers: [SottoTimer] = []
    private var storageError: String?
    private var operating: Set<String> = []
    init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sotto/timers.json"),
         notifications: any TimerNotifications = NativeTimerNotifications(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.file = file; self.notifications = notifications; self.now = now
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, let size = values.fileSize, size <= 1_000_000 else { throw ToolError.invalid("Invalid timer store") }
            let stored = try JSONDecoder().decode([SottoTimer].self, from: Data(contentsOf: file))
            guard stored.count <= 200, Set(stored.map(\.id)).count == stored.count,
                  stored.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 128 && $0.id.rangeOfCharacter(from: .controlCharacters) == nil && !$0.name.isEmpty && $0.name.count <= 120 && $0.name.rangeOfCharacter(from: .controlCharacters) == nil && $0.deadline.timeIntervalSince1970.isFinite }) else { throw ToolError.invalid("Invalid saved timers") }
            timers = stored
        } catch { storageError = "Saved timers could not be read. Existing data was preserved; no new timer or notification was created." }
    }
    private func checkStorage() throws {
        if let storageError { throw ToolError.unavailable(storageError) }
    }
    private func persist() throws {
        try checkStorage()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: file.path), (try file.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true { throw ToolError.denied("Timer storage cannot be a link") }
        let data = try JSONEncoder().encode(timers)
        guard timers.count <= 200, data.count <= 1_000_000 else { throw ToolError.unavailable("Timer storage is full. Clear old timers before adding another.") }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try Data(contentsOf: file) == data else { throw ToolError.unavailable("Timer save could not be verified") }
    }
    private func mutate(_ change: (inout [SottoTimer]) -> Void) throws {
        let old = timers; change(&timers)
        do { try persist() } catch { timers = old; throw error }
    }
    private func update(_ id: String, _ delivery: TimerDelivery) throws {
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].delivery != delivery else { return }
        try mutate { $0[index].delivery = delivery }
    }
    func list() throws -> [SottoTimer] { try checkStorage(); return timers }
    func start(seconds: Double, name: String) async throws -> ToolResult {
        try checkStorage(); try Task.checkCancellation()
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard seconds.isFinite, (1...2_592_000).contains(seconds), label.count <= 120,
              label.rangeOfCharacter(from: .controlCharacters) == nil else { throw ToolError.invalid("Use one second to 30 days and a timer name of at most 120 characters without control characters") }
        guard timers.filter({ $0.delivery != .cancellationPending && $0.deadline > now() }).count < 50 else { throw ToolError.unavailable("Cancel an active timer before adding another") }
        try notifications.checkAvailability()
        let timer = SottoTimer(id: "sotto.timer." + UUID().uuidString, name: label.isEmpty ? "Timer" : label, deadline: now().addingTimeInterval(seconds))
        try mutate { values in
            values.removeAll { $0.delivery != .cancellationPending && $0.deadline < now().addingTimeInterval(-86_400) }
            values.append(timer)
        }
        do {
            try await synchronize(timer.id, requestPermission: true)
            try Task.checkCancellation()
        } catch is CancellationError {
            // Persistence precedes any alert; cleanup is safe even if add() was
            // already accepted. A failed cleanup remains durably pending.
            _ = try? await cancel(id: timer.id)
            throw CancellationError()
        } catch {
            // Timer itself is already persisted. Preserve honest partial evidence.
            guard let current = timers.first(where: { $0.id == timer.id }) else { return ToolResult("Timer was cancelled while its notification was being prepared.", state: .cancelled) }
            if current.delivery == .cancellationPending { return startResult(current) }
            if timers.contains(where: { $0.id == timer.id && $0.delivery != .cancellationPending }) { try? update(timer.id, .failed) }
            return ToolResult("Timer saved, but its notification could not be verified. Check active timers before retrying.", data: Self.data(timers.first { $0.id == timer.id } ?? timer, at: now()), state: .partiallyCompleted)
        }
        guard let current = timers.first(where: { $0.id == timer.id }) else { return ToolResult("Timer was cancelled while its notification was being prepared.", state: .cancelled) }
        return startResult(current)
    }
    private func startResult(_ timer: SottoTimer) -> ToolResult {
        let message: String
        switch timer.delivery {
        case .scheduled: message = "Started \(timer.name). Its notification is scheduled; sleep, Focus or macOS restrictions may delay delivery."
        case .quiet: message = "Started \(timer.name), but visible alerts are restricted. Check Sotto; a banner or sound is not guaranteed."
        case .disabled: message = "Timer saved, but notifications are not allowed. Check Sotto's timers; no alert is guaranteed."
        case .elapsedUnverified: message = "The timer deadline passed while notification access was being checked. No new alert was scheduled; delivery is unverified."
        case .cancellationPending: message = "Timer cancellation is recorded; notification removal is still being verified."
        default: message = "Timer saved, but its notification scheduling is not verified. Check active timers before retrying."
        }
        return ToolResult(message, data: Self.data(timer, at: now()), state: timer.delivery == .scheduled ? .success : .partiallyCompleted)
    }
    private func finishCancellation(_ id: String) async throws {
        guard await notifications.remove(id) else { return }
        try mutate { $0.removeAll { $0.id == id } }
    }
    func cancel(id: String) async throws -> ToolResult {
        try checkStorage()
        guard let timer = timers.first(where: { $0.id == id }) else { throw ToolError.invalid("Choose an exact timer identifier from timers.list") }
        try update(id, .cancellationPending)
        if !operating.contains(id) {
            operating.insert(id); defer { operating.remove(id) }
            try await finishCancellation(id)
        }
        if let pending = timers.first(where: { $0.id == id }) {
            return ToolResult("Cancellation recorded for \(timer.name); notification removal is not yet verified. It will not be restored as an active timer.", data: Self.data(pending, at: now()), state: .partiallyCompleted)
        }
        return ToolResult("Cancelled \(timer.name). No pending or delivered notification remains for this timer.", data: .object(["id": .string(id)]))
    }
    private func synchronize(_ id: String, requestPermission: Bool) async throws {
        guard !operating.contains(id) else { return }
        operating.insert(id); defer { operating.remove(id) }
        guard let initial = timers.first(where: { $0.id == id }) else { return }
        if initial.delivery == .cancellationPending { try await finishCancellation(id); return }
        if initial.deadline <= now() { try update(id, .elapsedUnverified); return }
        let permission = try await notifications.permission(request: requestPermission)
        try Task.checkCancellation()
        guard let current = timers.first(where: { $0.id == id }) else { return }
        if current.delivery == .cancellationPending { try await finishCancellation(id); return }
        if current.deadline <= now() { try update(id, .elapsedUnverified); return }
        guard permission.canSchedule else { try update(id, .disabled); return }
        let pending = await notifications.pending()
        try Task.checkCancellation()
        if timers.first(where: { $0.id == id })?.delivery == .cancellationPending { try await finishCancellation(id); return }
        if current.deadline <= now() { try update(id, .elapsedUnverified); return }
        if !Self.matches(pending, timer: current) {
            try update(id, .needsScheduling)
            do { try await notifications.schedule(current, remaining: current.deadline.timeIntervalSince(now())) }
            catch {
                if timers.first(where: { $0.id == id })?.delivery == .cancellationPending { try await finishCancellation(id) }
                throw error
            }
        }
        if timers.first(where: { $0.id == id })?.delivery == .cancellationPending { try await finishCancellation(id); return }
        try Task.checkCancellation()
        if current.deadline <= now() { try update(id, .elapsedUnverified); return }
        let verified = await notifications.pending()
        if timers.first(where: { $0.id == id })?.delivery == .cancellationPending { try await finishCancellation(id); return }
        try update(id, Self.matches(verified, timer: current) ? (permission == .alerts ? .scheduled : .quiet) : .failed)
    }
    private static func matches(_ pending: [PendingTimerAlert], timer: SottoTimer) -> Bool {
        pending.contains { $0.id == timer.id && $0.date.map { abs($0.timeIntervalSince(timer.deadline)) <= 2 } == true }
    }
    /// No authorization prompts or expired-timer replay on launch/wake/list.
    func reconcile() async throws {
        try checkStorage()
        let cutoff = now().addingTimeInterval(-86_400)
        if timers.contains(where: { $0.deadline < cutoff && $0.delivery != .cancellationPending && !operating.contains($0.id) }) {
            try mutate { values in values.removeAll { $0.deadline < cutoff && $0.delivery != .cancellationPending && !operating.contains($0.id) } }
        }
        for id in timers.map(\.id) {
            try Task.checkCancellation()
            do { try await synchronize(id, requestPermission: false) }
            catch is CancellationError { throw CancellationError() }
            catch {
                if timers.first(where: { $0.id == id })?.delivery != .cancellationPending { try update(id, .failed) }
            }
        }
    }
    static func data(_ timer: SottoTimer, at date: Date = Date()) -> JSONValue {
        let elapsed = timer.deadline <= date
        let delivery = timer.delivery == .cancellationPending ? timer.delivery : elapsed ? .elapsedUnverified : timer.delivery
        return .object(["id": .string(timer.id), "name": .string(timer.name), "deadline": .string(ISO8601DateFormatter().string(from: timer.deadline)),
                        "remaining_seconds": .number(max(0, timer.deadline.timeIntervalSince(date))), "elapsed": .bool(elapsed),
                        "notification_state": .string(delivery.rawValue), "delivery_verified": .bool(false)])
    }
    func listing() async throws -> ToolResult {
        try await reconcile()
        let date = now()
        let all = try list()
        let active = all.filter { $0.deadline > date && $0.delivery != .cancellationPending }
        let elapsed = all.filter { $0.deadline <= date && $0.delivery != .cancellationPending }
        let pending = all.filter { $0.delivery == .cancellationPending }
        var lines = active.map { timer -> String in
            let seconds = Int(ceil(max(0, timer.deadline.timeIntervalSince(date))))
            let remaining = seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
            let note = timer.delivery == .scheduled ? "alert scheduled" : timer.delivery == .quiet ? "visible alerts restricted" : "alert not verified"
            return "\(timer.name): \(remaining) remaining · \(note)"
        }
        if active.isEmpty { lines = ["No active timers."] }
        if !elapsed.isEmpty { lines.append("\(elapsed.count) recent timer deadlines passed; notification delivery is unverified.") }
        if !pending.isEmpty { lines.append("\(pending.count) cancellations are awaiting notification-removal verification.") }
        return ToolResult(lines.joined(separator: "\n"), data: .object(["timers": .array(active.map { Self.data($0, at: date) }),
            "recent_elapsed": .array(elapsed.map { Self.data($0, at: date) }), "cancellations_pending": .array(pending.map { Self.data($0, at: date) }),
            "active_count": .number(Double(active.count))]))
    }
}
public enum SottoTimerMaintenance {
    public static func reconcile() async throws { try await TimerEngine.shared.reconcile() }
    public static func isTimerNotification(_ id: String) async -> Bool {
        (try? await TimerEngine.shared.list().contains { $0.id == id && $0.delivery != .cancellationPending }) ?? false
    }
}
struct TimerTool: Tool {
    let action: String
    let engine: TimerEngine
    init(action: String, engine: TimerEngine = .shared) { self.action = action; self.engine = engine }
    var descriptor: ToolDescriptor {
        let properties: [String: JSONValue] = action == "start" ? ["seconds": .object(["type": .string("number"), "description": .string("Duration in seconds, 1 to 2592000")]), "name": textProperty("Optional timer label, at most 120 characters")] : action == "cancel" ? ["id": textProperty("Exact timer identifier")] : [:]
        return ToolDescriptor(id: "timers." + action, description: "\(action.capitalized) native persistent timers. Future alerts are reconciled to original deadlines; expired timers are not restarted. Lists separate active, elapsed and cancellation-pending records. Notification scheduling is checked, not proof of delivery. Sleep/Focus/restrictions can delay alerts.", properties: properties,
                              required: action == "start" ? ["seconds"] : Array(properties.keys), risk: .reversible, capabilities: [.timers],
                              permissions: action == "start" ? ["Notifications (optional; delivery requires authorization)"] : [])
    }
    func execute(arguments: JSONValue) async throws -> ToolResult {
        try descriptor.validate(arguments); try Task.checkCancellation()
        switch action {
        case "start":
            guard case .number(let seconds) = arguments.object?["seconds"] else { throw ToolError.invalid("Provide seconds") }
            return try await engine.start(seconds: seconds, name: arguments.object?["name"]?.string ?? "")
        case "cancel": return try await engine.cancel(id: arguments.object?["id"]?.string ?? "")
        default: return try await engine.listing()
        }
    }
}
