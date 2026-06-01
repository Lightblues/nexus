import Foundation
import GRDB

/// Reads legacy JSON files from the Electron build (and from earlier Swift Phase 1/2)
/// and bulk-inserts them into the new SQLite database. Runs once: skipped when
/// nexus.db already contains data.
///
/// Source files we know about:
///   ~/.ea/nexus/data.json                       — active Pomodoro sessions
///   ~/.ea/nexus/archive/pomodoro-{YYYY}.json    — archived Pomodoro sessions
///   ~/.ea/nexus/tracker/{YYYY-MM-DD}.json       — daily Tracker records
enum LegacyMigration {
    struct Result {
        var pomodoroInserted = 0
        var trackerInserted = 0
        var renamedFiles: [URL] = []
        var skipped = false
    }

    /// Run migration if not already done. Idempotent — calling twice is safe.
    static func runIfNeeded(db: Database) async -> Result {
        var result = Result()

        // Skip if DB already has any data — assume migration already ran.
        let hasData: Bool = (try? await db.read { db in
            let n: Int = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pomodoro_sessions") ?? 0
            let m: Int = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracker_records") ?? 0
            return n > 0 || m > 0
        }) ?? false

        if hasData {
            result.skipped = true
            Log.app.info("Legacy migration: skipped (DB already populated)")
            return result
        }

        // --- Pomodoro: data.json ---
        if FileManager.default.fileExists(atPath: Paths.dataFile.path) {
            let n = await importPomodoroFile(Paths.dataFile, db: db)
            result.pomodoroInserted += n
            renameToBak(Paths.dataFile, into: &result.renamedFiles)
        }

        // --- Pomodoro: archive/*.json ---
        if let archives = try? FileManager.default.contentsOfDirectory(
            at: Paths.archiveDir, includingPropertiesForKeys: nil)
        {
            for url in archives where url.pathExtension == "json"
                && url.lastPathComponent.hasPrefix("pomodoro-")
            {
                let n = await importPomodoroArchive(url, db: db)
                result.pomodoroInserted += n
                renameToBak(url, into: &result.renamedFiles)
            }
        }

        // --- Tracker: tracker/*.json ---
        if let trackerFiles = try? FileManager.default.contentsOfDirectory(
            at: Paths.trackerDir, includingPropertiesForKeys: nil)
        {
            for url in trackerFiles where url.pathExtension == "json" {
                let n = await importTrackerFile(url, db: db)
                result.trackerInserted += n
                renameToBak(url, into: &result.renamedFiles)
            }
        }

        Log.app.info("Legacy migration complete: \(result.pomodoroInserted) pomodoro + \(result.trackerInserted) tracker rows; renamed \(result.renamedFiles.count) files")
        return result
    }

    // MARK: - Pomodoro

    /// data.json shape (from PomodoroData):
    /// { "sessions": [...], "meta": {...}, "schemaVersion": 1 }
    /// Older Electron files may have just the inner shape — handle both.
    private static func importPomodoroFile(_ url: URL, db: Database) async -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        // Try Swift-shape first
        if let parsed = try? Self.decoder.decode(PomodoroData.self, from: data) {
            return await insertSessions(parsed.sessions, db: db, sourceLabel: url.lastPathComponent)
        }
        // Fallback: bare array
        if let sessions = try? Self.decoder.decode([SessionRecord].self, from: data) {
            return await insertSessions(sessions, db: db, sourceLabel: url.lastPathComponent)
        }
        Log.app.warn("Could not decode \(url.lastPathComponent), skipping")
        return 0
    }

    /// pomodoro-{YYYY}.json was a bare [SessionRecord] array.
    private static func importPomodoroArchive(_ url: URL, db: Database) async -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        if let sessions = try? Self.decoder.decode([SessionRecord].self, from: data) {
            return await insertSessions(sessions, db: db, sourceLabel: url.lastPathComponent)
        }
        Log.app.warn("Could not decode archive \(url.lastPathComponent), skipping")
        return 0
    }

    private static func insertSessions(_ sessions: [SessionRecord], db: Database, sourceLabel: String) async -> Int {
        guard !sessions.isEmpty else { return 0 }
        do {
            try await db.write { db in
                for s in sessions {
                    try PomodoroRepository.insertRow(db: db, record: s)
                }
            }
            Log.app.info("\(sourceLabel): imported \(sessions.count) pomodoro sessions")
            return sessions.count
        } catch {
            Log.app.error("\(sourceLabel) batch insert failed: \(error)")
            return 0
        }
    }

    // MARK: - Tracker

    /// tracker/YYYY-MM-DD.json shape (from DailyTrackerData):
    /// { "date": "...", "version": 1, "records": [...], "meta": {...} }
    private static func importTrackerFile(_ url: URL, db: Database) async -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        if let parsed = try? Self.decoder.decode(DailyTrackerData.self, from: data) {
            return await insertRecords(parsed.records, db: db, sourceLabel: url.lastPathComponent)
        }
        // Older Electron files might have records at top level
        if let records = try? Self.decoder.decode([WindowActivityRecord].self, from: data) {
            return await insertRecords(records, db: db, sourceLabel: url.lastPathComponent)
        }
        Log.app.warn("Could not decode \(url.lastPathComponent), skipping")
        return 0
    }

    private static func insertRecords(_ records: [WindowActivityRecord], db: Database, sourceLabel: String) async -> Int {
        guard !records.isEmpty else { return 0 }
        do {
            try await db.write { db in
                for r in records {
                    try TrackerRepository.insertRow(db: db, record: r)
                }
            }
            Log.app.info("\(sourceLabel): imported \(records.count) tracker records")
            return records.count
        } catch {
            Log.app.error("\(sourceLabel) batch insert failed: \(error)")
            return 0
        }
    }

    // MARK: - File renaming

    /// Rename foo.json → foo.json.bak. If foo.json.bak already exists, append timestamp.
    private static func renameToBak(_ url: URL, into list: inout [URL]) {
        let fm = FileManager.default
        let bak = url.appendingPathExtension("bak")
        let target: URL
        if fm.fileExists(atPath: bak.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            target = url.appendingPathExtension("bak.\(stamp)")
        } else {
            target = bak
        }
        do {
            try fm.moveItem(at: url, to: target)
            list.append(target)
        } catch {
            Log.app.warn("Could not rename \(url.lastPathComponent) → \(target.lastPathComponent): \(error)")
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: str) { return d }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let d = f2.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                debugDescription: "Cannot parse date: \(str)")
        }
        return d
    }()
}

// MARK: - Legacy JSON shapes (kept around just for migration parsing)

private struct PomodoroData: Codable {
    var sessions: [SessionRecord]
}

private struct DailyTrackerData: Codable {
    var date: String
    var version: Int
    var records: [WindowActivityRecord]
}
