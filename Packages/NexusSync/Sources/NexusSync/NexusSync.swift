import Foundation
import GRDB

/// Schema entry point. The app's `Migrator` calls `registerMigrations` after registering its own.
public enum NexusSync {
    public static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("sync_v1") { db in
            try db.execute(sql: """
                ALTER TABLE tracker_records ADD COLUMN uid TEXT;
                UPDATE tracker_records SET uid = \(uuidSQL);
                CREATE UNIQUE INDEX tracker_records_uid ON tracker_records(uid);
                CREATE TABLE sync_outbox (
                    kind TEXT NOT NULL, id TEXT NOT NULL, updated_at INTEGER NOT NULL,
                    PRIMARY KEY (kind, id));
                CREATE TABLE sync_state (key TEXT PRIMARY KEY NOT NULL, value TEXT);
                CREATE TABLE sync_settings (
                    key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL, updated_at INTEGER NOT NULL);
                """)
            for sql in triggers { try db.execute(sql: sql) }
        }
    }

    /// Random UUID v4, lowercase.
    static let uuidSQL = """
        lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || \
        substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', 1 + (random() & 3), 1) || \
        substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))
        """

    /// `sync_state` key whose presence means a remote change is being applied, so triggers stay quiet.
    static let applyingKey = "applying"
    private static let nowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)"

    private static func enqueue(_ kind: String, _ id: String) -> String {
        """
        INSERT INTO sync_outbox (kind, id, updated_at)
        SELECT '\(kind)', \(id), \(nowMs)
         WHERE \(id) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sync_state WHERE key = '\(applyingKey)')
        ON CONFLICT (kind, id) DO UPDATE SET updated_at = excluded.updated_at;
        """
    }

    private static func trigger(_ name: String, _ event: String, _ table: String, _ body: [String]) -> String {
        "CREATE TRIGGER \(name) AFTER \(event) ON \(table) BEGIN\n\(body.joined(separator: "\n"))\nEND"
    }

    /// Insert, update, and delete triggers for each synced table. An update also enqueues the old key,
    /// so a rename pushes a tombstone for the old name.
    static var triggers: [String] {
        var out: [String] = []
        for (table, kind, key) in [
            ("pomodoro_sessions", "pomodoro_session", "id"),
            ("pomodoro_session_tags", "pomodoro_session", "session_id"),
            ("pomodoro_projects", "pomodoro_project", "name"),
            ("pomodoro_tag_catalog", "pomodoro_tag", "name"),
        ] {
            out.append(trigger("\(table)_sync_insert", "INSERT", table, [enqueue(kind, "NEW.\(key)")]))
            out.append(trigger("\(table)_sync_update", "UPDATE", table, [enqueue(kind, "OLD.\(key)"), enqueue(kind, "NEW.\(key)")]))
            out.append(trigger("\(table)_sync_delete", "DELETE", table, [enqueue(kind, "OLD.\(key)")]))
        }
        out.append(trigger("tracker_records_sync_insert", "INSERT", "tracker_records", [
            "UPDATE tracker_records SET uid = \(uuidSQL) WHERE id = NEW.id AND uid IS NULL;",
            enqueue("tracker_record", "(SELECT uid FROM tracker_records WHERE id = NEW.id)"),
        ]))
        out.append(trigger("tracker_records_sync_update", "UPDATE", "tracker_records",
                           [enqueue("tracker_record", "OLD.uid"), enqueue("tracker_record", "NEW.uid")]))
        out.append(trigger("tracker_records_sync_delete", "DELETE", "tracker_records", [enqueue("tracker_record", "OLD.uid")]))
        return out
    }
}
