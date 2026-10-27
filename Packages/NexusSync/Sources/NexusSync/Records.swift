import Foundation
import GRDB

/// One record on the wire (`sync.md`). `rev` and `device` are set only on records the server returns.
public struct SyncRecord: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    /// Unix epoch milliseconds of the edit.
    public var updatedAt: Int64
    public var deleted: Bool
    public var body: JSONValue?
    public var rev: Int64?
    public var device: String?

    public init(kind: String, id: String, updatedAt: Int64, deleted: Bool = false, body: JSONValue? = nil,
                rev: Int64? = nil, device: String? = nil) {
        self.kind = kind; self.id = id; self.updatedAt = updatedAt; self.deleted = deleted
        self.body = deleted ? nil : body; self.rev = rev; self.device = device
    }

    var key: String { "\(kind)\u{0}\(id)" }
}

public struct PushResult: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    public var rev: Int64?
    public var stale: SyncRecord?
    public var error: String?

    public init(kind: String, id: String, rev: Int64? = nil, stale: SyncRecord? = nil, error: String? = nil) {
        self.kind = kind; self.id = id; self.rev = rev; self.stale = stale; self.error = error
    }
}

public struct PullPage: Codable, Equatable, Sendable {
    public var records: [SyncRecord]
    public var cursor: Int64
    public var more: Bool

    public init(records: [SyncRecord], cursor: Int64, more: Bool) {
        self.records = records; self.cursor = cursor; self.more = more
    }
}

/// Row ↔ record mapping for every synced table kind. Settings live in `Settings.swift`.
struct RecordKind: Sendable {
    enum ColumnType: Sendable { case int, text, bool }
    struct Column: Sendable {
        let field: String, name: String, type: ColumnType, required: Bool
        init(_ field: String, _ name: String, _ type: ColumnType, required: Bool = false) {
            self.field = field; self.name = name; self.type = type; self.required = required
        }
    }

    let kind: String
    let table: String
    /// Column holding the record id.
    let key: String
    let columns: [Column]
    /// `pomodoro_session` carries its tag names from `pomodoro_session_tags`.
    var hasTags = false

    static let all: [RecordKind] = [
        RecordKind(kind: "pomodoro_session", table: "pomodoro_sessions", key: "id", columns: [
            Column("kind", "kind", .text, required: true),
            Column("startTime", "start_time", .int, required: true),
            Column("endTime", "end_time", .int, required: true),
            Column("duration", "duration", .int, required: true),
            Column("project", "project", .text),
            Column("task", "task", .text),
            Column("completedFully", "completed_fully", .bool, required: true),
        ], hasTags: true),
        RecordKind(kind: "pomodoro_project", table: "pomodoro_projects", key: "name", columns: [
            Column("color", "color", .text, required: true),
            Column("createdAt", "created_at", .int, required: true),
        ]),
        RecordKind(kind: "pomodoro_tag", table: "pomodoro_tag_catalog", key: "name", columns: [
            Column("createdAt", "created_at", .int, required: true),
        ]),
        RecordKind(kind: "tracker_record", table: "tracker_records", key: "uid", columns: [
            Column("startTime", "start_time", .int, required: true),
            Column("endTime", "end_time", .int, required: true),
            Column("duration", "duration", .int, required: true),
            Column("app", "app", .text, required: true),
            Column("bundleId", "bundle_id", .text),
            Column("title", "title", .text),
            Column("contextProject", "context_project", .text),
            Column("contextFile", "context_file", .text),
            Column("contextUrl", "context_url", .text),
            Column("contextDomain", "context_domain", .text),
            Column("contextRawTitle", "context_raw_title", .text),
        ]),
    ]

    static func named(_ kind: String) -> RecordKind? { all.first { $0.kind == kind } }

    /// The current row as a record, or a tombstone when the row is gone.
    func record(id: String, updatedAt: Int64, db: Database) throws -> SyncRecord {
        let names = columns.map(\.name).joined(separator: ", ")
        guard let row = try Row.fetchOne(db, sql: "SELECT \(names) FROM \(table) WHERE \(key) = ?", arguments: [id]) else {
            return SyncRecord(kind: kind, id: id, updatedAt: updatedAt, deleted: true)
        }
        var body: [String: JSONValue] = [:]
        for column in columns { body[column.field] = Self.json(row[column.name], column.type) }
        if hasTags {
            let tags = try String.fetchAll(db, sql: "SELECT tag FROM pomodoro_session_tags WHERE session_id = ? ORDER BY tag", arguments: [id])
            body["tags"] = .array(tags.map(JSONValue.string))
        }
        return SyncRecord(kind: kind, id: id, updatedAt: updatedAt, body: .object(body))
    }

    /// Writes a pulled record into its table. Returns false when a live body lacks a required field.
    func write(_ record: SyncRecord, db: Database) throws -> Bool {
        if record.deleted {
            if hasTags { try db.execute(sql: "DELETE FROM pomodoro_session_tags WHERE session_id = ?", arguments: [record.id]) }
            try db.execute(sql: "DELETE FROM \(table) WHERE \(key) = ?", arguments: [record.id])
            return true
        }
        var values: [DatabaseValue] = [record.id.databaseValue]
        for column in columns {
            let value = Self.databaseValue(record.body?[column.field], column.type)
            if column.required && value.isNull { return false }
            values.append(value)
        }
        let names = [key] + columns.map(\.name)
        let updates = columns.map { "\($0.name) = excluded.\($0.name)" }.joined(separator: ", ")
        try db.execute(sql: """
            INSERT INTO \(table) (\(names.joined(separator: ", "))) VALUES (\(databaseQuestionMarks(count: names.count)))
            ON CONFLICT (\(key)) DO UPDATE SET \(updates)
            """, arguments: StatementArguments(values))
        if hasTags {
            try db.execute(sql: "DELETE FROM pomodoro_session_tags WHERE session_id = ?", arguments: [record.id])
            if case .array(let tags)? = record.body?["tags"] {
                for case .string(let tag) in tags {
                    try db.execute(sql: "INSERT OR IGNORE INTO pomodoro_session_tags (session_id, tag) VALUES (?, ?)",
                                   arguments: [record.id, tag])
                }
            }
        }
        return true
    }

    func localIDs(db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT \(key) FROM \(table) WHERE \(key) IS NOT NULL")
    }

    private static func json(_ value: DatabaseValue, _ type: ColumnType) -> JSONValue {
        switch (value.storage, type) {
        case (.int64(let i), .bool): return .bool(i != 0)
        case (.int64(let i), _): return .number(Double(i))
        case (.double(let d), .bool): return .bool(d != 0)
        case (.double(let d), _): return .number(d)
        case (.string(let s), _): return .string(s)
        default: return .null
        }
    }

    private static func databaseValue(_ value: JSONValue?, _ type: ColumnType) -> DatabaseValue {
        switch (value, type) {
        case (.number(let d)?, .int) where Int64(exactly: d.rounded()) != nil: return Int64(d.rounded()).databaseValue
        case (.bool(let b)?, .bool): return b.databaseValue
        case (.number(let d)?, .bool): return (d != 0).databaseValue
        case (.string(let s)?, .text): return s.databaseValue
        default: return .null
        }
    }
}
