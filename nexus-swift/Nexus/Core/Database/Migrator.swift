import Foundation
import GRDB

/// Versioned schema migrations. Each migration runs once per database;
/// GRDB tracks applied migrations in `grdb_migrations` table.
enum Migrator {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        // Useful in development: erase + reapply when migrations change.
        // Disabled in release.
        #if DEBUG
        // m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1_pomodoro_tracker") { db in
            // --- Pomodoro ---
            try db.create(table: "pomodoro_sessions") { t in
                t.primaryKey("id", .text).notNull()
                t.column("kind", .text).notNull()                  // work | shortBreak | longBreak
                t.column("start_time", .integer).notNull()         // unix epoch seconds
                t.column("end_time", .integer).notNull()
                t.column("duration", .integer).notNull()           // seconds
                t.column("project", .text)
                t.column("task", .text)
                t.column("completed_fully", .boolean).notNull()
            }
            try db.create(indexOn: "pomodoro_sessions", columns: ["start_time"])

            try db.create(table: "pomodoro_session_tags") { t in
                t.column("session_id", .text)
                    .notNull()
                    .references("pomodoro_sessions", onDelete: .cascade)
                t.column("tag", .text).notNull()
                t.primaryKey(["session_id", "tag"])
            }

            // --- Tracker ---
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
            // Projects: name + display color. Project name is the natural key —
            // session.project is a free-form string today, this catalog tracks
            // which names exist + their assigned colors.
            try db.create(table: "pomodoro_projects") { t in
                t.primaryKey("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("created_at", .integer).notNull()
            }
            // Tag catalog: just the set of tag names ever used. Letting users
            // explicitly add/remove tags here is what `pomodoro_session_tags`
            // can't do (you'd have to retag a session to register a new tag).
            try db.create(table: "pomodoro_tag_catalog") { t in
                t.primaryKey("name", .text).notNull()
                t.column("created_at", .integer).notNull()
            }
        }

        return m
    }
}
