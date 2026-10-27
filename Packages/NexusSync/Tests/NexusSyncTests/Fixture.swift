import Foundation
import GRDB
@testable import NexusSync

/// The app's v1–v4 schema, copied from `Nexus/Core/Database/Migrator.swift`.
enum Fixture {
    static func appMigrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1_pomodoro_tracker") { db in
            try db.create(table: "pomodoro_sessions") { t in
                t.primaryKey("id", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("start_time", .integer).notNull()
                t.column("end_time", .integer).notNull()
                t.column("duration", .integer).notNull()
                t.column("project", .text)
                t.column("task", .text)
                t.column("completed_fully", .boolean).notNull()
            }
            try db.create(indexOn: "pomodoro_sessions", columns: ["start_time"])
            try db.create(table: "pomodoro_session_tags") { t in
                t.column("session_id", .text).notNull().references("pomodoro_sessions", onDelete: .cascade)
                t.column("tag", .text).notNull()
                t.primaryKey(["session_id", "tag"])
            }
            try db.create(table: "tracker_records") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start_time", .integer).notNull()
                t.column("end_time", .integer).notNull()
                t.column("duration", .integer).notNull()
                t.column("app", .text).notNull()
                t.column("bundle_id", .text)
                t.column("title", .text)
                t.column("context_project", .text)
                t.column("context_file", .text)
                t.column("context_url", .text)
                t.column("context_domain", .text)
                t.column("context_raw_title", .text)
            }
            try db.create(indexOn: "tracker_records", columns: ["start_time"])
            try db.create(indexOn: "tracker_records", columns: ["app", "start_time"])
        }
        m.registerMigration("v2_projects_tags_catalog") { db in
            try db.create(table: "pomodoro_projects") { t in
                t.primaryKey("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("created_at", .integer).notNull()
            }
            try db.create(table: "pomodoro_tag_catalog") { t in
                t.primaryKey("name", .text).notNull()
                t.column("created_at", .integer).notNull()
            }
        }
        m.registerMigration("v3_uploader") { db in
            try db.create(table: "upload_history") { t in
                t.primaryKey("id", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("original_name", .text).notNull()
                t.column("timestamp", .integer).notNull()
                t.column("original_size", .integer).notNull()
                t.column("compressed_size", .integer).notNull()
                t.column("width", .integer).notNull()
                t.column("height", .integer).notNull()
                t.column("format", .text).notNull()
                t.column("path", .text)
                t.column("cdn_url", .text).notNull()
                t.column("sha", .text).notNull()
            }
            try db.create(indexOn: "upload_history", columns: ["timestamp"])
            try db.create(table: "upload_paths") { t in
                t.primaryKey("path", .text).notNull()
                t.column("last_used", .integer).notNull()
            }
        }
        m.registerMigration("v4_uploader_repo_meta") { db in
            try db.alter(table: "upload_history") { t in
                t.add(column: "github_owner", .text)
                t.add(column: "github_repo", .text)
                t.add(column: "github_branch", .text)
            }
        }
        return m
    }

    /// An in-memory database on the app schema plus the sync migration, as the app's `Migrator` will build it.
    static func database(before: ((Database) throws -> Void)? = nil) throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try appMigrator().migrate(queue)
        if let before { try queue.write(before) }
        var m = appMigrator()
        NexusSync.registerMigrations(&m)
        try m.migrate(queue)
        return queue
    }

    // MARK: - Writes the way the app's repositories make them

    static func insertSession(_ db: Database, id: String, start: Int = 1_761_530_000, project: String? = "nexus", tags: [String] = []) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO pomodoro_sessions (id, kind, start_time, end_time, duration, project, task, completed_fully)
            VALUES (?, 'work', ?, ?, 1500, ?, 'sync', 1)
            """, arguments: [id, start, start + 1500, project])
        try db.execute(sql: "DELETE FROM pomodoro_session_tags WHERE session_id = ?", arguments: [id])
        for tag in tags {
            try db.execute(sql: "INSERT INTO pomodoro_session_tags (session_id, tag) VALUES (?, ?)", arguments: [id, tag])
        }
    }

    static func insertTracker(_ db: Database, start: Int = 1_761_530_000, app: String = "Code") throws {
        try db.execute(sql: """
            INSERT INTO tracker_records (start_time, end_time, duration, app, bundle_id, title, context_project, context_file,
                                         context_url, context_domain, context_raw_title)
            VALUES (?, ?, 5, ?, 'com.example', NULL, 'nexus', 'a.swift', NULL, NULL, NULL)
            """, arguments: [start, start + 5, app])
    }

    static func outbox(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT kind || ' ' || id FROM sync_outbox ORDER BY kind, id")
    }

    static func outbox(_ queue: DatabaseQueue) throws -> [String] { try queue.read { db in try outbox(db) } }

    /// Every synced row as text, without local autoincrement ids, for comparing two databases.
    static func dump(_ queue: DatabaseQueue) throws -> [String] {
        try queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT 's ' || id || ' ' || kind || ' ' || start_time || ' ' || end_time || ' ' || duration || ' ' ||
                       ifnull(project, '-') || ' ' || ifnull(task, '-') || ' ' || completed_fully FROM pomodoro_sessions
                UNION ALL SELECT 'st ' || session_id || ' ' || tag FROM pomodoro_session_tags
                UNION ALL SELECT 'p ' || name || ' ' || color || ' ' || created_at FROM pomodoro_projects
                UNION ALL SELECT 't ' || name || ' ' || created_at FROM pomodoro_tag_catalog
                UNION ALL SELECT 'r ' || uid || ' ' || start_time || ' ' || end_time || ' ' || duration || ' ' || app || ' ' ||
                       ifnull(bundle_id, '-') || ' ' || ifnull(title, '-') || ' ' || ifnull(context_project, '-') || ' ' ||
                       ifnull(context_file, '-') FROM tracker_records
                ORDER BY 1
                """)
        }
    }

    static let defaultConfig: [String: JSONValue] = [
        "pomodoro": .object(["workDuration": .number(25), "autoStartBreak": .bool(true)]),
        "tracker": .object(["enrichApps": .array([.string("Code"), .string("Google Chrome")])]),
        "uploader": .object(["github": .object(["token": .string(""), "branch": .string("main")])]),
    ]
}

/// `config.json` stand-in.
final class MemorySettings: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String: JSONValue]
    private(set) var saves = 0

    init(_ value: [String: JSONValue] = Fixture.defaultConfig) { self.value = value }

    var current: [String: JSONValue] { lock.lock(); defer { lock.unlock() }; return value }
    var leaves: [String: JSONValue] { Settings.flatten(current) }

    func set(_ path: String, _ leaf: JSONValue) {
        lock.lock(); defer { lock.unlock() }
        var flat = Settings.flatten(value)
        flat[path] = leaf
        value = Settings.unflatten(flat)
    }

    func load() async throws -> [String: JSONValue] { current }
    func save(_ settings: [String: JSONValue]) async throws { replace(settings) }

    private func replace(_ settings: [String: JSONValue]) {
        lock.lock(); defer { lock.unlock() }
        value = settings
        saves += 1
    }
}

/// In-memory server following `sync.md`: last write wins by `updatedAt`, ties keep the stored copy, rev-ordered pull pages.
actor FakeServer: SyncAPI {
    nonisolated let endpoint: String
    private var records: [String: SyncRecord] = [:]
    private var rev: Int64 = 0
    private let pageSize: Int
    private(set) var pushBatches: [Int] = []
    private(set) var pulls = 0
    /// Per-item error codes keyed by record id.
    var itemErrors: [String: String] = [:]
    var failing = false

    init(endpoint: String = "fake://server", pageSize: Int = 1000) {
        self.endpoint = endpoint; self.pageSize = pageSize
    }

    func setFailing(_ on: Bool) { failing = on }
    func setItemError(_ id: String, _ code: String?) { itemErrors[id] = code }

    func push(device: String, items: [SyncRecord]) async throws -> [PushResult] {
        if failing { throw SyncError.http(status: 500, code: "internal") }
        pushBatches.append(items.count)
        return items.map { item in
            if let code = itemErrors[item.id] { return PushResult(kind: item.kind, id: item.id, error: code) }
            if let current = records[item.key], item.updatedAt <= current.updatedAt {
                return PushResult(kind: item.kind, id: item.id, stale: current)
            }
            rev += 1
            records[item.key] = SyncRecord(kind: item.kind, id: item.id, updatedAt: item.updatedAt, deleted: item.deleted,
                                           body: item.body, rev: rev, device: device)
            return PushResult(kind: item.kind, id: item.id, rev: rev)
        }
    }

    func pull(since cursor: Int64) async throws -> PullPage {
        if failing { throw SyncError.http(status: 500, code: "internal") }
        pulls += 1
        let newer = records.values.filter { ($0.rev ?? 0) > cursor }.sorted { ($0.rev ?? 0) < ($1.rev ?? 0) }
        let page = Array(newer.prefix(pageSize))
        return PullPage(records: page, cursor: page.last?.rev ?? cursor, more: newer.count > page.count)
    }

    /// Writes a record as another Mac would.
    func seed(_ record: SyncRecord, device: String = "other") {
        rev += 1
        var stored = record
        stored.rev = rev; stored.device = device
        records[record.key] = stored
    }

    func record(_ kind: String, _ id: String) -> SyncRecord? { records["\(kind)\u{0}\(id)"] }
    var all: [SyncRecord] { Array(records.values) }
}
