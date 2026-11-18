import Foundation
import Darwin
import SottoTools

public enum WorkflowStepState: String, Codable, Sendable { case pending, running, succeeded, uncertain, skipped }
public enum WorkflowRunState: String, Codable, Sendable { case active, paused, completed, completedWithSkips }
public struct WorkflowStepRecord: Codable, Sendable {
    public let definition: JSONValue
    public var state: WorkflowStepState = .pending
    public var result: ToolResult?
    public var durationSeconds: Double?
}
public struct WorkflowRunRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public var updatedAt: Date
    public var revision: Int
    public var state: WorkflowRunState
    public var steps: [WorkflowStepRecord]
    public var note: String?
    public var hasUncertainSteps: Bool { steps.contains { $0.state == .running || $0.state == .uncertain } }
    public var terminal: Bool { state == .completed || state == .completedWithSkips }
    public var remaining: [JSONValue] { steps.filter { $0.state == .pending }.map(\.definition) }
    public var data: JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))) ?? .null }
}

/// One owner per execution, across both tasks and app processes. Kernel releases
/// the advisory lease after a crash; lock files are never unlinked while used.
final class WorkflowExecutionLease: @unchecked Sendable {
    private let descriptor: Int32
    init(url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ToolError.unavailable("Could not lock this workflow recovery record") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor); throw ToolError.denied("This workflow execution is already active. Wait for it to stop.")
        }
    }
    deinit { _ = flock(descriptor, LOCK_UN); close(descriptor) }
}
/// Journal before dispatch, flush before native effects. Unknown outcomes are
/// never silently reset to pending, including after process termination.
public final class WorkflowJournal: @unchecked Sendable {
    public static let shared = WorkflowJournal()
    private let directory: URL
    private let lock = NSRecursiveLock()
    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sotto/WorkflowRecovery")) {
        self.directory = directory
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try directory.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw ToolError.denied("Recovery storage must be a local directory, not a link") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    func lease(_ id: UUID) throws -> WorkflowExecutionLease {
        try lock.withLock { try prepare(); return try WorkflowExecutionLease(url: directory.appendingPathComponent(id.uuidString + ".lock")) }
    }
    public func load(_ id: UUID) throws -> WorkflowRunRecord { try lock.withLock { try read(id) } }
    private func read(_ id: UUID) throws -> WorkflowRunRecord {
        let file = url(id)
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, let size = values.fileSize, size <= 1_000_000 else { throw ToolError.unavailable("Invalid or oversized recovery record") }
        let record = try JSONDecoder().decode(WorkflowRunRecord.self, from: Data(contentsOf: file))
        guard record.id == id, record.revision > 0, (1...10).contains(record.steps.count), record.name.count <= 80,
              record.steps.allSatisfy({ $0.state != .succeeded || $0.result?.state == .success }) else { throw ToolError.unavailable("This recovery record is inconsistent. It was not executed.") }
        return record
    }
    private func write(_ record: WorkflowRunRecord) throws {
        try prepare()
        let data = try JSONEncoder().encode(record)
        guard data.count <= 1_000_000 else { throw ToolError.unavailable("Recovery evidence exceeds the local size limit") }
        let target = url(record.id)
        try data.write(to: target, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let file = try FileHandle(forWritingTo: target)
        defer { try? file.close() }
        try file.synchronize()
        // Flush the rename's parent too. Failure prevents subsequent native effects.
        let parent = open(directory.path, O_RDONLY | O_NOFOLLOW)
        guard parent >= 0 else { throw ToolError.unavailable("Recovery directory could not be synchronized") }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw ToolError.unavailable("Recovery directory could not be synchronized") }
        guard try Data(contentsOf: target) == data else { throw ToolError.unavailable("Recovery save could not be verified") }
    }
    public func create(name: String, steps: [JSONValue]) throws -> WorkflowRunRecord {
        try lock.withLock {
            guard (1...10).contains(steps.count), name.count <= 80 else { throw ToolError.invalid("Invalid workflow recovery plan") }
            var existing = try records()
            // Completed records expire after a week or make room for newer runs.
            // Interrupted/uncertain executions are never silently discarded.
            for old in existing.reversed() where old.terminal && (Date().timeIntervalSince(old.updatedAt) > 7 * 86_400 || existing.count >= 50) {
                if (try? remove(old.id)) != nil { existing.removeAll { $0.id == old.id } }
            }
            // Do not silently discard recoverable actions to make space.
            guard existing.count < 50 else { throw ToolError.unavailable("Recovery storage is full. Forget old execution records in Workflows before starting another routine.") }
            let now = Date()
            let record = WorkflowRunRecord(id: UUID(), name: name, createdAt: now, updatedAt: now, revision: 1, state: .active, steps: steps.map { WorkflowStepRecord(definition: $0) })
            try write(record); return record
        }
    }
    func update(_ record: WorkflowRunRecord) throws -> WorkflowRunRecord {
        try lock.withLock {
            let current = try read(record.id)
            guard current.revision == record.revision, current.revision < Int.max,
                  current.steps.map(\.definition) == record.steps.map(\.definition) else { throw ToolError.denied("Recovery changed since it was reviewed. Review it again.") }
            var updated = record; updated.revision += 1; updated.updatedAt = Date()
            try write(updated); return updated
        }
    }
    public func records() throws -> [WorkflowRunRecord] {
        try lock.withLock {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            guard files.count <= 50 else { throw ToolError.unavailable("Too many recovery records. Review local recovery storage.") }
            return try files.map { file in
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { throw ToolError.unavailable("Invalid recovery filename") }
                return try read(id)
            }.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    public func remove(_ id: UUID) throws {
        let ownership = try lease(id)
        defer { withExtendedLifetime(ownership) {} }
        try lock.withLock {
            _ = try read(id)
            try FileManager.default.removeItem(at: url(id))
        }
    }
}
