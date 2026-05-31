import Foundation
import GRDB

/// One-shot migration of project + tag catalogs into the v2 SQLite tables.
///
/// Sources, in priority order:
///  1. Existing `pomodoro_projects` / `pomodoro_tag_catalog` (skip if already populated)
///  2. The user's current config.json (if it has the legacy `pomodoro.projects`
///     / `pomodoro.tags` arrays — kept around as `LegacyPomodoroCatalog`)
///  3. Backfill from session history: any project name or tag that appears in
///     `pomodoro_sessions` but not in the catalogs.
///
/// Runs at app launch after the DB schema migrations.
enum CatalogMigration {
    static func runIfNeeded(db: Database) async {
        do {
            // Skip if catalogs already populated.
            let alreadyPopulated: Bool = try await db.read { db in
                let p: Int = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pomodoro_projects") ?? 0
                let t: Int = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pomodoro_tag_catalog") ?? 0
                return p > 0 || t > 0
            }
            if alreadyPopulated {
                return
            }

            // 1. Try to read legacy config arrays. Tolerant of missing fields.
            var importedProjects = 0
            var importedTags = 0
            if let data = try? Data(contentsOf: Paths.configFile),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pomo = json["pomodoro"] as? [String: Any]
            {
                if let projects = pomo["projects"] as? [[String: Any]] {
                    try await db.write { db in
                        for p in projects {
                            guard let name = p["name"] as? String, !name.isEmpty else { continue }
                            let color = (p["color"] as? String) ?? "#3B82F6"
                            try PomodoroRepository.upsertProject(db: db, name: name, color: color)
                            importedProjects += 1
                        }
                    }
                }
                if let tags = pomo["tags"] as? [String] {
                    try await db.write { db in
                        for t in tags where !t.isEmpty {
                            try PomodoroRepository.upsertTag(db: db, name: t)
                            importedTags += 1
                        }
                    }
                }
            }

            // 2. Backfill from session rows. Catches anything sessions reference
            //    that wasn't in the legacy config (or fresh installs that just
            //    have migrated session history).
            try await db.write { db in
                let projectNames = try String.fetchAll(db, sql: """
                    SELECT DISTINCT project FROM pomodoro_sessions
                     WHERE project IS NOT NULL AND project != ''
                    """)
                for p in projectNames {
                    try PomodoroRepository.upsertProject(db: db, name: p, color: nil)
                }
                let tagNames = try String.fetchAll(db, sql: """
                    SELECT DISTINCT tag FROM pomodoro_session_tags WHERE tag != ''
                    """)
                for t in tagNames {
                    try PomodoroRepository.upsertTag(db: db, name: t)
                }
            }

            // 3. If still nothing — give the user a starter set.
            try await db.write { db in
                let projectCount: Int = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pomodoro_projects") ?? 0
                if projectCount == 0 {
                    try PomodoroRepository.upsertProject(db: db, name: "default", color: "#3B82F6")
                }
                let tagCount: Int = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pomodoro_tag_catalog") ?? 0
                if tagCount == 0 {
                    for t in ["work", "study", "personal"] {
                        try PomodoroRepository.upsertTag(db: db, name: t)
                    }
                }
            }

            Log.app.info("Catalog migration: imported \(importedProjects) projects + \(importedTags) tags from config; backfilled rest from session history")

            // 4. Strip the legacy fields from config.json so we don't re-import
            //    next time and so future config saves don't carry stale data.
            //    (Keep a .bak just in case.)
            stripLegacyFieldsFromConfig()
        } catch {
            Log.app.error("Catalog migration failed: \(error)")
        }
    }

    /// Read config.json, drop `pomodoro.projects` + `pomodoro.tags`, write back.
    /// Best-effort — if the file isn't there or we can't parse it, do nothing.
    /// Handles the case where config.json is a symlink (mackup users): we
    /// resolve and write to the symlink's target via Data.write(to:) which
    /// follows symlinks, instead of `replaceItemAt` which would replace the
    /// link itself.
    private static func stripLegacyFieldsFromConfig() {
        let url = Paths.configFile
        guard let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        guard var pomo = json["pomodoro"] as? [String: Any],
              pomo["projects"] != nil || pomo["tags"] != nil
        else { return }
        // Backup first.
        let bak = url.appendingPathExtension("pre-catalog-migration.bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: url, to: bak)

        pomo.removeValue(forKey: "projects")
        pomo.removeValue(forKey: "tags")
        json["pomodoro"] = pomo
        guard let out = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys])
        else { return }
        // Resolve symlink so we write to the real file (mackup target dir).
        let target = (try? URL(fileURLWithPath: FileManager.default
            .destinationOfSymbolicLink(atPath: url.path))) ?? url
        do {
            // Direct write — preserves the symlink (no replaceItemAt) and
            // works whether or not the target itself is a symlink.
            try out.write(to: target, options: .atomic)
            Log.app.info("Stripped legacy projects/tags from config.json (backup at \(bak.lastPathComponent))")
        } catch {
            Log.app.warn("Could not strip legacy fields: \(error)")
        }
    }
}
