import Foundation
import GRDB

/// SQL-backed storage for window-activity records. Replaces TrackerStore + per-day JSON.
/// Tracker writes one row every 5s when user is active. The "merge consecutive same-app+file"
/// optimization happens here: we keep a published `lastRecordId` and `extendLastRecord()`
/// updates the row in place rather than writing a new one.
@MainActor
final class TrackerRepository: ObservableObject {
    /// Today's records — projected for the live UI updates. Refreshed on insert/extend.
    @Published private(set) var todayRecords: [WindowActivityRecord] = []
    @Published private(set) var todaySummary: [String: TimeInterval] = [:]

    private let db: Database
    /// Row id of the most recent record, used for merge extension.
    private var lastRowId: Int64?
    /// In-memory shadow of the last record so the merge predicate can compare without a SELECT.
    private(set) var lastRecord: WindowActivityRecord?

    init(database: Database) {
        self.db = database
    }

    func bootstrap() async {
        await refreshToday()
        // Load last row id + record for merge continuation across launches.
        struct LastRow: Sendable {
            let id: Int64
            let record: WindowActivityRecord
        }
        do {
            let last: LastRow? = try await db.read { db in
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT * FROM tracker_records ORDER BY id DESC LIMIT 1
                    """) else { return nil }
                return LastRow(id: row["id"], record: Self.recordFromRow(row))
            }
            if let last {
                self.lastRowId = last.id
                self.lastRecord = last.record
            }
        } catch {
            Log.tracker.warn("Bootstrap last-record load failed: \(error)")
        }
    }

    // MARK: - Mutations

    /// Insert a fresh record (new app or new file).
    func insert(_ record: WindowActivityRecord) async {
        do {
            let newId = try await db.write { db -> Int64 in
                try Self.insertRow(db: db, record: record)
                return db.lastInsertedRowID
            }
            lastRowId = newId
            lastRecord = record
            await refreshToday()
        } catch {
            Log.tracker.error("insert failed: \(error)")
        }
    }

    /// Extend the most recent record's endTime in place. Used when user stays
    /// on the same app+file across multiple polls.
    func extendLastRecord(to endTime: Date) async {
        guard let id = lastRowId, var last = lastRecord else { return }
        last.endTime = endTime
        last.duration = endTime.timeIntervalSince(last.startTime)
        lastRecord = last
        // Capture into immutable locals so the @Sendable db.write closure
        // doesn't reference the (mutable) `last` var via implicit self.
        let newDuration = Int(last.duration)
        let endTs = Int(endTime.timeIntervalSince1970)
        do {
            try await db.write { db in
                try db.execute(sql: """
                    UPDATE tracker_records SET end_time = ?, duration = ? WHERE id = ?
                    """, arguments: [
                        endTs,
                        newDuration,
                        id
                    ])
            }
            await refreshTodayIfStale()
        } catch {
            Log.tracker.error("extendLastRecord failed: \(error)")
        }
    }

    // MARK: - Queries

    /// Records for a given calendar day (local tz). Used by the Tracker UI date picker.
    func records(on day: Date) async -> [WindowActivityRecord] {
        do {
            return try await db.read { db in
                let (start, end) = Self.dayBounds(day)
                return try Row.fetchAll(db, sql: """
                    SELECT * FROM tracker_records
                     WHERE start_time >= ? AND start_time < ?
                     ORDER BY start_time
                    """, arguments: [start, end])
                    .map(Self.recordFromRow)
            }
        } catch {
            Log.tracker.error("records(on:) failed: \(error)")
            return []
        }
    }

    /// Per-app totals for a day. SQL-aggregated; doesn't load full records.
    func appSummary(on day: Date) async -> [String: TimeInterval] {
        do {
            return try await db.read { db in
                let (start, end) = Self.dayBounds(day)
                let rows = try Row.fetchAll(db, sql: """
                    SELECT app, SUM(duration) AS sec
                      FROM tracker_records
                     WHERE start_time >= ? AND start_time < ?
                     GROUP BY app
                    """, arguments: [start, end])
                var out: [String: TimeInterval] = [:]
                for r in rows {
                    if let a: String = r["app"], let s: Int = r["sec"] {
                        out[a] = TimeInterval(s)
                    }
                }
                return out
            }
        } catch { return [:] }
    }

    func totalActiveTime(on day: Date) async -> TimeInterval {
        do {
            return try await db.read { db in
                let (start, end) = Self.dayBounds(day)
                let n: Int = try Int.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(duration),0) FROM tracker_records
                     WHERE start_time >= ? AND start_time < ?
                    """, arguments: [start, end]) ?? 0
                return TimeInterval(n)
            }
        } catch { return 0 }
    }

    // MARK: - Live "today" projection

    private func refreshToday() async {
        let today = Date()
        let recs = await records(on: today)
        let summary = await appSummary(on: today)
        await MainActor.run {
            self.todayRecords = recs
            self.todaySummary = summary
        }
    }

    /// Cheap update used by extend(): only the last record's endTime changed,
    /// so just splice it into todayRecords without re-querying.
    private func refreshTodayIfStale() async {
        guard let last = lastRecord else { return }
        let cal = Calendar.current
        guard cal.isDateInToday(last.startTime) else { return }
        if let idx = todayRecords.lastIndex(where: { $0.startTime == last.startTime && $0.app == last.app }) {
            todayRecords[idx] = last
            // Recompute summary for that one app
            todaySummary[last.app] = todayRecords.filter { $0.app == last.app }.map(\.duration).reduce(0, +)
        }
    }

    // MARK: - Statics (used by Migration too)

    nonisolated static func insertRow(db: GRDB.Database, record: WindowActivityRecord) throws {
        try db.execute(sql: """
            INSERT INTO tracker_records
                (start_time, end_time, duration, app, bundle_id, title,
                 context_project, context_file, context_url, context_domain, context_raw_title)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                Int(record.startTime.timeIntervalSince1970),
                Int(record.endTime.timeIntervalSince1970),
                Int(record.duration),
                record.app,
                record.bundleId,
                record.title,
                record.context?.project,
                record.context?.file,
                record.context?.url,
                record.context?.domain,
                record.context?.rawTitle
            ])
    }

    nonisolated private static func recordFromRow(_ row: Row) -> WindowActivityRecord {
        let start = Date(timeIntervalSince1970: TimeInterval(row["start_time"] as Int))
        let end = Date(timeIntervalSince1970: TimeInterval(row["end_time"] as Int))
        let duration = TimeInterval(row["duration"] as Int)
        var ctx = ActivityContext()
        ctx.project = row["context_project"]
        ctx.file = row["context_file"]
        ctx.url = row["context_url"]
        ctx.domain = row["context_domain"]
        ctx.rawTitle = row["context_raw_title"]
        return WindowActivityRecord(
            startTime: start, endTime: end, duration: duration,
            app: row["app"], bundleId: row["bundle_id"], title: row["title"],
            context: ctx.isEmpty ? nil : ctx
        )
    }

    nonisolated private static func dayBounds(_ day: Date) -> (Int, Int) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970))
    }
}
