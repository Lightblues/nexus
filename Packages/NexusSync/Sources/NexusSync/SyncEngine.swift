import Foundation
import GRDB

public struct SyncReport: Equatable, Sendable {
    /// Writes the server stored.
    public var pushed = 0
    /// Writes the server answered with its newer copy, which was applied locally.
    public var stale = 0
    /// Pulled records applied locally.
    public var pulled = 0
    /// `kind id: code` for items the server refused; they stay in the outbox.
    public var failed: [String] = []
}

/// Pushes local changes and pulls remote ones (`sync.md`, client rules). One `sync()` runs at a time.
public actor SyncEngine {
    public static let maxBatchItems = 500
    public static let maxBatchBytes = 256 * 1024

    private let db: any DatabaseWriter
    private let api: any SyncAPI
    private let settings: (any SettingsStore)?

    public init(db: any DatabaseWriter, api: any SyncAPI, settings: (any SettingsStore)?) {
        self.db = db; self.api = api; self.settings = settings
    }

    /// This database's stable device id, created on first use.
    public func deviceID() async throws -> String {
        try await db.write { db in
            if let id = try State.get(db, "device") { return id }
            let id = UUID().uuidString.lowercased()
            try State.set(db, "device", id)
            return id
        }
    }

    public func sync() async throws -> SyncReport {
        var report = SyncReport()
        let device = try await deviceID()
        var (cursor, server, snapshot) = try await db.read { db in
            (Int64(try State.get(db, "cursor") ?? "") ?? 0, try State.get(db, "server"), try State.snapshot(db))
        }
        let endpoint = api.endpoint
        if server != endpoint {
            try await db.write { db in
                try db.execute(sql: "DELETE FROM sync_settings")
                try State.set(db, "cursor", "0")
            }
            snapshot = [:]
            let seen: Set<String>
            (cursor, seen) = try await pull(from: 0, firstContact: true, snapshot: &snapshot, report: &report)
            let stamp = Self.nowMs()
            try await db.write { db in
                try Self.enqueueUnseen(seen, at: stamp, db: db)
                try State.set(db, "server", endpoint)
            }
        }
        try await pushSettings(device: device, snapshot: &snapshot, report: &report)
        try await pushOutbox(device: device, report: &report)
        _ = try await pull(from: cursor, firstContact: false, snapshot: &snapshot, report: &report)
        return report
    }

    // MARK: - Push

    private func pushSettings(device: String, snapshot: inout [String: JSONValue], report: inout SyncReport) async throws {
        guard let settings else { return }
        let current = Settings.flatten(try await settings.load())
        let stamp = Self.nowMs()
        var pending = current.keys.sorted().compactMap { key -> SyncRecord? in
            guard let value = current[key], snapshot[key] != value else { return nil }
            return SyncRecord(kind: "setting", id: key, updatedAt: stamp, body: .object(["value": value]))
        }[...]
        while !pending.isEmpty {
            let batch = try Self.batch(pending.map { $0 })
            pending = pending.dropFirst(batch.count)
            let results = try await api.push(device: device, items: batch)
            var edits: [SnapshotEdit] = []
            var stale: [SyncRecord] = []
            for (item, result) in zip(batch, results) {
                if let error = result.error { report.failed.append("\(item.kind) \(item.id): \(error)"); continue }
                guard let value = item.body?["value"] else { continue }
                snapshot[item.id] = value
                edits.append(SnapshotEdit(key: item.id, value: value, updatedAt: item.updatedAt))
                if let record = result.stale { stale.append(record) } else { report.pushed += 1 }
            }
            report.stale += stale.count
            edits += try await applySettings(stale, firstContact: false, snapshot: &snapshot)
            let done = edits
            try await db.write { db in try State.save(done, db: db) }
        }
    }

    private func pushOutbox(device: String, report: inout SyncReport) async throws {
        var after: Int64 = 0
        while true {
            let since = after
            let batch = try await db.read { db in try Self.outboxBatch(after: since, db: db) }
            guard let last = batch.last else { return }
            let results = try await api.push(device: device, items: batch.map(\.record))
            guard results.count == batch.count else { throw SyncError.badResponse }
            let stale = results.compactMap(\.stale)
            try await db.write { db in
                for (item, result) in zip(batch, results) where result.rev != nil && result.stale == nil {
                    try db.execute(sql: "DELETE FROM sync_outbox WHERE kind = ? AND id = ? AND updated_at = ?",
                                   arguments: [item.record.kind, item.record.id, item.record.updatedAt])
                }
                _ = try Self.apply(stale, db: db)
            }
            for (item, result) in zip(batch, results) {
                if let error = result.error { report.failed.append("\(item.record.kind) \(item.record.id): \(error)") }
                else if result.stale != nil { report.stale += 1 }
                else { report.pushed += 1 }
            }
            after = last.rowid
        }
    }

    struct OutboxItem: Sendable { let rowid: Int64; let record: SyncRecord }

    /// Up to `maxBatchItems` outbox entries after `rowid`, as whole current records, within `maxBatchBytes`.
    static func outboxBatch(after rowid: Int64, db: Database) throws -> [OutboxItem] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT rowid, kind, id, updated_at FROM sync_outbox WHERE rowid > ? ORDER BY rowid LIMIT ?
            """, arguments: [rowid, maxBatchItems])
        var out: [OutboxItem] = []
        var bytes = 0
        for row in rows {
            guard let kind = RecordKind.named(row["kind"]) else { continue }
            let record = try kind.record(id: row["id"], updatedAt: row["updated_at"], db: db)
            let size = try JSONEncoder().encode(record).count
            if !out.isEmpty && bytes + size > maxBatchBytes { break }
            bytes += size
            out.append(OutboxItem(rowid: row["rowid"], record: record))
        }
        return out
    }

    /// The longest prefix within `maxBatchItems` and `maxBatchBytes` (at least one item).
    static func batch(_ items: [SyncRecord]) throws -> [SyncRecord] {
        var bytes = 0
        var out: [SyncRecord] = []
        for item in items.prefix(maxBatchItems) {
            let size = try JSONEncoder().encode(item).count
            if !out.isEmpty && bytes + size > maxBatchBytes { break }
            bytes += size
            out.append(item)
        }
        return out
    }

    // MARK: - Pull

    /// Pulls pages until `more` is false, applying each page in one write. Returns the cursor and every key seen.
    private func pull(from start: Int64, firstContact: Bool, snapshot: inout [String: JSONValue],
                      report: inout SyncReport) async throws -> (Int64, Set<String>) {
        var cursor = start
        var seen = Set<String>()
        while true {
            let page = try await api.pull(since: cursor)
            let edits = try await applySettings(page.records.filter { $0.kind == "setting" }, firstContact: firstContact, snapshot: &snapshot)
            let records = page.records.filter { $0.kind != "setting" }
            let next = page.cursor
            let applied = try await db.write { db -> Int in
                let applied = try Self.apply(records, db: db)
                try State.save(edits, db: db)
                try State.set(db, "cursor", String(next))
                return applied
            }
            report.pulled += applied + edits.count
            for record in page.records { seen.insert(record.key) }
            cursor = next
            if !page.more || page.records.isEmpty { return (cursor, seen) }
        }
    }

    /// Applies remote records with the triggers silenced. A record loses to an unsent local edit with a newer `updatedAt`.
    static func apply(_ records: [SyncRecord], db: Database) throws -> Int {
        guard !records.isEmpty else { return 0 }
        try State.set(db, NexusSync.applyingKey, "1")
        var applied = 0
        for record in records {
            guard let kind = RecordKind.named(record.kind) else { continue }
            let pending = try Int64.fetchOne(db, sql: "SELECT updated_at FROM sync_outbox WHERE kind = ? AND id = ?",
                                             arguments: [record.kind, record.id])
            if let pending, pending > record.updatedAt { continue }
            guard try kind.write(record, db: db) else { continue }
            try db.execute(sql: "DELETE FROM sync_outbox WHERE kind = ? AND id = ?", arguments: [record.kind, record.id])
            applied += 1
        }
        try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [NexusSync.applyingKey])
        return applied
    }

    /// Applies remote settings to the store and the in-memory snapshot; returns the snapshot rows to write.
    /// On first contact the server wins every key; later, a key edited locally since the snapshot is left for the next push.
    private func applySettings(_ records: [SyncRecord], firstContact: Bool,
                               snapshot: inout [String: JSONValue]) async throws -> [SnapshotEdit] {
        guard let settings, !records.isEmpty else { return [] }
        var current = Settings.flatten(try await settings.load())
        var changed = false
        var edits: [SnapshotEdit] = []
        for record in records {
            if record.deleted {
                snapshot[record.id] = nil
                edits.append(SnapshotEdit(key: record.id, value: nil, updatedAt: record.updatedAt))
                continue
            }
            guard let value = record.body?["value"] else { continue }
            if !firstContact && current[record.id] != snapshot[record.id] { continue }
            if current[record.id] != value { current[record.id] = value; changed = true }
            snapshot[record.id] = value
            edits.append(SnapshotEdit(key: record.id, value: value, updatedAt: record.updatedAt))
        }
        if changed { try await settings.save(Settings.unflatten(current)) }
        return edits
    }

    /// First contact: local rows the server did not send are queued for the push.
    static func enqueueUnseen(_ seen: Set<String>, at stamp: Int64, db: Database) throws {
        let insert = try db.cachedStatement(sql: "INSERT OR IGNORE INTO sync_outbox (kind, id, updated_at) VALUES (?, ?, ?)")
        for kind in RecordKind.all {
            for id in try kind.localIDs(db: db) where !seen.contains("\(kind.kind)\u{0}\(id)") {
                try insert.execute(arguments: [kind.kind, id, stamp])
            }
        }
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

struct SnapshotEdit: Sendable {
    let key: String
    /// nil removes the key.
    let value: JSONValue?
    let updatedAt: Int64
}

enum State {
    static func get(_ db: Database, _ key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [key])
    }

    static func set(_ db: Database, _ key: String, _ value: String) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)", arguments: [key, value])
    }

    static func snapshot(_ db: Database) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT key, value FROM sync_settings") {
            out[row["key"]] = try JSONValue.decode(row["value"])
        }
        return out
    }

    static func save(_ edits: [SnapshotEdit], db: Database) throws {
        for edit in edits {
            if let value = edit.value {
                try db.execute(sql: "INSERT OR REPLACE INTO sync_settings (key, value, updated_at) VALUES (?, ?, ?)",
                               arguments: [edit.key, try value.encoded(), edit.updatedAt])
            } else {
                try db.execute(sql: "DELETE FROM sync_settings WHERE key = ?", arguments: [edit.key])
            }
        }
    }
}
