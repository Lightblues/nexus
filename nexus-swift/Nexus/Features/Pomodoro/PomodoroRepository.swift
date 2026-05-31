import Foundation
import GRDB

/// SQL-backed storage for Pomodoro sessions. Replaces PomodoroStore.
/// All write paths fan out to refreshing @Published projections so views update.
@MainActor
final class PomodoroRepository: ObservableObject {
    /// Last session metadata for the popover draft + sessionsSinceLongBreak counter.
    /// These were previously in PomodoroData.meta — now derived from the most
    /// recent session row.
    @Published private(set) var lastSession: SessionMetadata = .empty
    @Published private(set) var sessionsSinceLongBreak: Int = 0
    /// Today's work-session count + total duration. Refreshed on insert.
    @Published private(set) var todayCount: Int = 0
    @Published private(set) var todayDuration: TimeInterval = 0
    /// Live projection of the project + tag catalogs. Bound by Settings + popover UI.
    @Published private(set) var projects: [ProjectConfig] = []
    @Published private(set) var tagCatalog: [String] = []

    private let db: Database

    init(database: Database) {
        self.db = database
    }

    /// Load derived projections (last session, today's count, catalogs). Call from bootstrap.
    func refresh() async {
        struct Snapshot: Sendable {
            let last: SessionRecord?
            let sessionsSinceLongBreak: Int
            let count: Int
            let duration: TimeInterval
            let projects: [ProjectConfig]
            let tags: [String]
        }
        do {
            let snap: Snapshot = try await db.read { db in
                let last = try Self.fetchLastSession(db)
                let sessionsSinceLongBreak = Self.computeSessionsSinceLongBreak(db: db) ?? 0
                let (count, duration) = try Self.todaySummary(db: db)
                let projects = try Self.fetchProjects(db: db)
                let tags = try Self.fetchTags(db: db)
                return Snapshot(last: last, sessionsSinceLongBreak: sessionsSinceLongBreak,
                                count: count, duration: duration,
                                projects: projects, tags: tags)
            }
            self.lastSession = snap.last?.metadata ?? .empty
            self.sessionsSinceLongBreak = snap.sessionsSinceLongBreak
            self.todayCount = snap.count
            self.todayDuration = snap.duration
            self.projects = snap.projects
            self.tagCatalog = snap.tags
        } catch {
            Log.pomodoro.error("Repository refresh failed: \(error)")
        }
    }

    // MARK: - Mutations

    func insert(_ record: SessionRecord) async {
        do {
            try await db.write { db in
                try Self.insertRow(db: db, record: record)
                // Auto-register the project + tags so they show up in the
                // catalog even if user hasn't gone through Settings.
                if let p = record.project, !p.isEmpty {
                    try Self.upsertProject(db: db, name: p, color: nil)
                }
                for tag in record.tags {
                    try Self.upsertTag(db: db, name: tag)
                }
            }
            await refresh()
        } catch {
            Log.pomodoro.error("Insert session failed: \(error)")
        }
    }

    func update(_ record: SessionRecord) async {
        do {
            try await db.write { db in
                try db.execute(sql: """
                    UPDATE pomodoro_sessions
                       SET kind = ?, start_time = ?, end_time = ?, duration = ?,
                           project = ?, task = ?, completed_fully = ?
                     WHERE id = ?
                    """, arguments: [
                        record.kind.rawValue,
                        Int(record.startTime.timeIntervalSince1970),
                        Int(record.endTime.timeIntervalSince1970),
                        Int(record.duration),
                        record.project,
                        record.task,
                        record.completedFully,
                        record.id.uuidString
                    ])
                try db.execute(sql: "DELETE FROM pomodoro_session_tags WHERE session_id = ?",
                               arguments: [record.id.uuidString])
                for tag in record.tags {
                    try db.execute(sql: "INSERT INTO pomodoro_session_tags(session_id, tag) VALUES(?, ?)",
                                   arguments: [record.id.uuidString, tag])
                }
            }
            await refresh()
        } catch {
            Log.pomodoro.error("Update session failed: \(error)")
        }
    }

    func updateLastSessionMetadata(_ meta: SessionMetadata) async {
        // Just refresh the published projection — there's no separate row to write.
        // Next session insert will use this metadata.
        lastSession = meta
        // Persist by writing to a "preferences" KV in the DB? No — we already
        // derive lastSession from the most recent session at bootstrap. To make
        // the *unsaved* draft survive restarts before the next session, we
        // store it in UserDefaults.
        Self.persistDraft(meta)
    }

    // MARK: - Queries

    /// Sessions for a single calendar day (local tz).
    func sessions(on day: Date) async -> [SessionRecord] {
        do {
            return try await db.read { db in
                let (start, end) = Self.dayBounds(day)
                return try Self.fetchSessions(db: db, range: start..<end)
            }
        } catch {
            Log.pomodoro.error("sessions(on:) failed: \(error)")
            return []
        }
    }

    /// Daily counts for the activity calendar. Returns [date string → work session count].
    /// Uses SQL aggregation — does not load full session rows.
    func dailyCounts(from: Date, to: Date) async -> [String: Int] {
        do {
            return try await db.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT date(start_time, 'unixepoch', 'localtime') AS day,
                           COUNT(*) AS n
                      FROM pomodoro_sessions
                     WHERE kind = 'work'
                       AND start_time >= ? AND start_time < ?
                     GROUP BY day
                    """, arguments: [Int(from.timeIntervalSince1970), Int(to.timeIntervalSince1970)])
                var out: [String: Int] = [:]
                for r in rows {
                    if let day: String = r["day"], let n: Int = r["n"] {
                        out[day] = n
                    }
                }
                return out
            }
        } catch {
            Log.pomodoro.error("dailyCounts failed: \(error)")
            return [:]
        }
    }

    /// Hours per day for the weekly bar chart. Returns [date string → hours].
    func dailyHours(from: Date, to: Date) async -> [String: Double] {
        do {
            return try await db.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT date(start_time, 'unixepoch', 'localtime') AS day,
                           SUM(duration) AS sec
                      FROM pomodoro_sessions
                     WHERE kind = 'work'
                       AND start_time >= ? AND start_time < ?
                     GROUP BY day
                    """, arguments: [Int(from.timeIntervalSince1970), Int(to.timeIntervalSince1970)])
                var out: [String: Double] = [:]
                for r in rows {
                    if let day: String = r["day"], let sec: Int = r["sec"] {
                        out[day] = Double(sec) / 3600.0
                    }
                }
                return out
            }
        } catch {
            Log.pomodoro.error("dailyHours failed: \(error)")
            return [:]
        }
    }

    /// All distinct projects mentioned in stored sessions (for autocomplete).
    func knownProjects() async -> [String] {
        do {
            return try await db.read { db in
                try String.fetchAll(db, sql: """
                    SELECT DISTINCT project FROM pomodoro_sessions
                     WHERE project IS NOT NULL AND project != ''
                     ORDER BY project
                    """)
            }
        } catch {
            return []
        }
    }

    /// Database-wide summary — total sessions, total focused seconds, span.
    /// Used by Stats page header. Single SQL query.
    struct DBSummary: Sendable, Equatable {
        let totalWorkSessions: Int
        let totalFocusSeconds: TimeInterval
        let firstSession: Date?
        let lastSession: Date?
    }

    func dbSummary() async -> DBSummary {
        do {
            return try await db.read { db in
                let row = try Row.fetchOne(db, sql: """
                    SELECT COUNT(*) AS n,
                           COALESCE(SUM(duration), 0) AS sec,
                           MIN(start_time) AS first_ts,
                           MAX(start_time) AS last_ts
                      FROM pomodoro_sessions
                     WHERE kind = 'work'
                    """)
                let n: Int = row?["n"] ?? 0
                let sec: Int = row?["sec"] ?? 0
                let firstTs: Int? = row?["first_ts"]
                let lastTs: Int? = row?["last_ts"]
                return DBSummary(
                    totalWorkSessions: n,
                    totalFocusSeconds: TimeInterval(sec),
                    firstSession: firstTs.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    lastSession: lastTs.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            }
        } catch {
            return DBSummary(totalWorkSessions: 0, totalFocusSeconds: 0,
                             firstSession: nil, lastSession: nil)
        }
    }

    // MARK: - Project + tag CRUD

    func addProject(name: String, color: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await db.write { db in
                try Self.upsertProject(db: db, name: trimmed, color: color)
            }
            await refresh()
        } catch { Log.pomodoro.error("addProject failed: \(error)") }
    }

    func updateProjectColor(name: String, color: String) async {
        do {
            try await db.write { db in
                try db.execute(sql: "UPDATE pomodoro_projects SET color = ? WHERE name = ?",
                               arguments: [color, name])
            }
            await refresh()
        } catch { Log.pomodoro.error("updateProjectColor failed: \(error)") }
    }

    func deleteProject(name: String) async {
        do {
            try await db.write { db in
                try db.execute(sql: "DELETE FROM pomodoro_projects WHERE name = ?",
                               arguments: [name])
            }
            await refresh()
        } catch { Log.pomodoro.error("deleteProject failed: \(error)") }
    }

    func addTag(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await db.write { db in
                try Self.upsertTag(db: db, name: trimmed)
            }
            await refresh()
        } catch { Log.pomodoro.error("addTag failed: \(error)") }
    }

    func deleteTag(_ name: String) async {
        do {
            try await db.write { db in
                try db.execute(sql: "DELETE FROM pomodoro_tag_catalog WHERE name = ?",
                               arguments: [name])
            }
            await refresh()
        } catch { Log.pomodoro.error("deleteTag failed: \(error)") }
    }

    // MARK: - Statics (used by Migration too)

    nonisolated static func insertRow(db: GRDB.Database, record: SessionRecord) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO pomodoro_sessions
                (id, kind, start_time, end_time, duration, project, task, completed_fully)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                record.id.uuidString,
                record.kind.rawValue,
                Int(record.startTime.timeIntervalSince1970),
                Int(record.endTime.timeIntervalSince1970),
                Int(record.duration),
                record.project,
                record.task,
                record.completedFully
            ])
        try db.execute(sql: "DELETE FROM pomodoro_session_tags WHERE session_id = ?",
                       arguments: [record.id.uuidString])
        for tag in record.tags {
            try db.execute(sql: "INSERT INTO pomodoro_session_tags(session_id, tag) VALUES(?, ?)",
                           arguments: [record.id.uuidString, tag])
        }
    }

    /// Insert a project if absent, otherwise leave the existing color alone (unless one is provided).
    nonisolated static func upsertProject(db: GRDB.Database, name: String, color: String?) throws {
        let now = Int(Date().timeIntervalSince1970)
        if let color {
            try db.execute(sql: """
                INSERT INTO pomodoro_projects(name, color, created_at)
                VALUES(?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET color = excluded.color
                """, arguments: [name, color, now])
        } else {
            // Auto-add path: pick a stable default color from name hash.
            let defaultColor = autoColor(for: name)
            try db.execute(sql: """
                INSERT INTO pomodoro_projects(name, color, created_at)
                VALUES(?, ?, ?)
                ON CONFLICT(name) DO NOTHING
                """, arguments: [name, defaultColor, now])
        }
    }

    nonisolated static func upsertTag(db: GRDB.Database, name: String) throws {
        let now = Int(Date().timeIntervalSince1970)
        try db.execute(sql: """
            INSERT INTO pomodoro_tag_catalog(name, created_at)
            VALUES(?, ?)
            ON CONFLICT(name) DO NOTHING
            """, arguments: [name, now])
    }

    /// Stable color from name — same hash function as TrackerColors so a project
    /// named "VSCode" gets the same hue across the app.
    private nonisolated static func autoColor(for name: String) -> String {
        let palette = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444",
                       "#8B5CF6", "#EC4899", "#14B8A6", "#6366F1",
                       "#06B6D4", "#F97316", "#84CC16", "#A855F7"]
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    nonisolated static func fetchProjects(db: GRDB.Database) throws -> [ProjectConfig] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT name, color FROM pomodoro_projects ORDER BY created_at, name
            """)
        return rows.map { ProjectConfig(name: $0["name"], color: $0["color"]) }
    }

    nonisolated static func fetchTags(db: GRDB.Database) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT name FROM pomodoro_tag_catalog ORDER BY created_at, name
            """)
    }

    nonisolated private static func fetchLastSession(_ db: GRDB.Database) throws -> SessionRecord? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT * FROM pomodoro_sessions
             WHERE kind = 'work'
             ORDER BY start_time DESC LIMIT 1
            """) else { return nil }
        return try sessionFromRow(db: db, row: row)
    }

    nonisolated private static func fetchSessions(db: GRDB.Database, range: Range<Int>) throws -> [SessionRecord] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM pomodoro_sessions
             WHERE start_time >= ? AND start_time < ?
             ORDER BY start_time
            """, arguments: [range.lowerBound, range.upperBound])
        return try rows.map { try Self.sessionFromRow(db: db, row: $0) }
    }

    nonisolated private static func sessionFromRow(db: GRDB.Database, row: Row) throws -> SessionRecord {
        let id = UUID(uuidString: row["id"]) ?? UUID()
        let kind = SessionKind(rawValue: row["kind"]) ?? .work
        let startTime = Date(timeIntervalSince1970: TimeInterval(row["start_time"] as Int))
        let endTime = Date(timeIntervalSince1970: TimeInterval(row["end_time"] as Int))
        let duration = TimeInterval(row["duration"] as Int)
        let project: String? = row["project"]
        let task: String? = row["task"]
        let completedFully: Bool = row["completed_fully"]

        let tags = try String.fetchAll(db, sql: """
            SELECT tag FROM pomodoro_session_tags WHERE session_id = ?
            """, arguments: [id.uuidString])

        return SessionRecord(
            id: id, kind: kind,
            startTime: startTime, endTime: endTime, duration: duration,
            project: project, tags: tags, task: task,
            completedFully: completedFully
        )
    }

    nonisolated private static func todaySummary(db: GRDB.Database) throws -> (count: Int, duration: TimeInterval) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let row = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) AS n, COALESCE(SUM(duration),0) AS sec
              FROM pomodoro_sessions
             WHERE kind = 'work' AND start_time >= ? AND start_time < ?
            """, arguments: [
                Int(start.timeIntervalSince1970),
                Int(end.timeIntervalSince1970)
            ])
        let n: Int = row?["n"] ?? 0
        let sec: Int = row?["sec"] ?? 0
        return (n, TimeInterval(sec))
    }

    nonisolated private static func computeSessionsSinceLongBreak(db: GRDB.Database) -> Int? {
        // Walk backwards from latest work session until we hit a long break.
        do {
            let rows = try Row.fetchAll(db, sql: """
                SELECT kind FROM pomodoro_sessions
                 ORDER BY start_time DESC LIMIT 50
                """)
            var count = 0
            for r in rows {
                let kind = (r["kind"] as String?) ?? ""
                if kind == "longBreak" { break }
                if kind == "work" { count += 1 }
            }
            return count
        } catch {
            return nil
        }
    }

    nonisolated private static func dayBounds(_ day: Date) -> (Int, Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970))
    }

    // MARK: - Draft metadata persistence (UserDefaults)

    private static let draftKey = "site.easonsi.nexus.pomodoroDraft"

    static func persistDraft(_ meta: SessionMetadata) {
        if let data = try? JSONEncoder().encode(meta) {
            UserDefaults.standard.set(data, forKey: draftKey)
        }
    }

    static func loadPersistedDraft() -> SessionMetadata? {
        guard let data = UserDefaults.standard.data(forKey: draftKey) else { return nil }
        return try? JSONDecoder().decode(SessionMetadata.self, from: data)
    }
}

private extension SessionRecord {
    var metadata: SessionMetadata {
        SessionMetadata(project: project, tags: tags, task: task)
    }
}
