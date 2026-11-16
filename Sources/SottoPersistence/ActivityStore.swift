import Foundation
import GRDB

public struct Activity: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: String
    public var date: Date
    public var tool: String
    public var summary: String
    public var succeeded: Bool
    public init(tool: String, summary: String, succeeded: Bool) { id = UUID().uuidString; date = Date(); self.tool = tool; self.summary = summary; self.succeeded = succeeded }
}
public actor ActivityStore {
    private let db: DatabaseQueue
    public init(path: String) throws {
        db = try DatabaseQueue(path: path)
        var migrations = DatabaseMigrator()
        migrations.registerMigration("activity-v1") { db in
            try db.create(table: "activity") { t in t.primaryKey("id", .text); t.column("date", .datetime).notNull(); t.column("tool", .text).notNull(); t.column("summary", .text).notNull(); t.column("succeeded", .boolean).notNull() }
        }
        try migrations.migrate(db)
    }
    public func append(_ item: Activity) throws { try db.write { try item.insert($0) } }
    public func recent() throws -> [Activity] { try db.read { try Activity.order(Column("date").desc).limit(100).fetchAll($0) } }
    public func purge(days: Int) throws { try db.write { db in _ = try Activity.filter(Column("date") < Date().addingTimeInterval(-Double(days) * 86400)).deleteAll(db) } }
    public func clear() throws { try db.write { db in try db.execute(sql: "PRAGMA secure_delete = ON"); _ = try Activity.deleteAll(db) }; try db.vacuum() }
}
