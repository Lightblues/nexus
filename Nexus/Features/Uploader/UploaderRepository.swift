import Foundation
import GRDB

/// SQL-backed storage for image uploads. Mirrors PomodoroRepository structure:
/// @Published projections refresh after each mutation; nonisolated `static`
/// helpers do the actual DB work so they can run inside `db.write { ... }`
/// closures without crossing actor boundaries.
@MainActor
final class UploaderRepository: ObservableObject {
    @Published private(set) var history: [UploadRecord] = []
    @Published private(set) var recentPaths: [String] = []

    /// Cap on history rows. Match the Electron build to keep migration UX
    /// consistent across rewrites.
    static let historyCap = 100
    static let pathsCap = 10
    /// Thumbnail edge size used for cached preview WebP/JPEGs.
    static let thumbnailSize = 200

    private let db: Database

    init(database: Database) {
        self.db = database
    }

    func bootstrap() async {
        await refresh()
    }

    func refresh() async {
        struct Snapshot: Sendable {
            let history: [UploadRecord]
            let paths: [String]
        }
        do {
            let snap: Snapshot = try await db.read { db in
                let h = try Self.fetchHistory(db)
                let p = try Self.fetchPaths(db)
                return Snapshot(history: h, paths: p)
            }
            self.history = snap.history
            self.recentPaths = snap.paths
        } catch {
            Log.uploader.error("Repository refresh failed: \(error)")
        }
    }

    // MARK: - Mutations

    /// Insert a new upload record. If `thumbnailData` is given, write it to
    /// the cache directory keyed by id. Bumps recent_paths and trims history
    /// if we're over `historyCap`.
    func add(_ record: UploadRecord, thumbnailData: Data?) async {
        do {
            try await db.write { db in
                try Self.insertRow(db, record: record)
                if let path = record.path, !path.isEmpty {
                    try Self.upsertPath(db, path: path)
                }
                try Self.trimHistory(db, cap: Self.historyCap)
                try Self.trimPaths(db, cap: Self.pathsCap)
            }
            // Persist the thumbnail outside the DB write — it's a file op,
            // not transactional with the row insert. Worst case: row exists
            // without a thumbnail; the UI shows a placeholder.
            if let data = thumbnailData {
                try? Self.writeThumbnail(id: record.id, data: data)
            }
            await refresh()
        } catch {
            Log.uploader.error("Insert upload row failed: \(error)")
        }
    }

    func delete(id: String) async {
        do {
            try await db.write { db in
                try db.execute(sql: "DELETE FROM upload_history WHERE id = ?", arguments: [id])
            }
            Self.removeThumbnail(id: id)
            await refresh()
        } catch {
            Log.uploader.error("Delete upload row failed: \(error)")
        }
    }

    /// Path on disk where the thumbnail for `id` lives, or nil if not cached.
    nonisolated func thumbnailURL(id: String) -> URL? {
        let url = Paths.uploaderCacheDir.appendingPathComponent("\(id).webp")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Static SQL helpers (nonisolated; safe to call inside db.write)

    private nonisolated static func fetchHistory(_ db: GRDB.Database) throws -> [UploadRecord] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, filename, original_name, timestamp, original_size, compressed_size,
                   width, height, format, path, cdn_url, sha,
                   github_owner, github_repo, github_branch
              FROM upload_history
             ORDER BY timestamp DESC
        """)
        return rows.compactMap(decode(_:))
    }

    private nonisolated static func fetchPaths(_ db: GRDB.Database) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT path FROM upload_paths
             ORDER BY last_used DESC
        """)
        return rows.compactMap { $0["path"] as String? }
    }

    private nonisolated static func insertRow(_ db: GRDB.Database, record: UploadRecord) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO upload_history
              (id, filename, original_name, timestamp, original_size, compressed_size,
               width, height, format, path, cdn_url, sha,
               github_owner, github_repo, github_branch)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            record.id,
            record.filename,
            record.originalName,
            Int(record.timestamp.timeIntervalSince1970 * 1000),
            record.originalSize,
            record.compressedSize,
            record.width,
            record.height,
            record.format.rawValue,
            record.path,
            record.cdnUrl,
            record.sha,
            record.githubOwner,
            record.githubRepo,
            record.githubBranch
        ])
    }

    private nonisolated static func upsertPath(_ db: GRDB.Database, path: String) throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        try db.execute(sql: """
            INSERT INTO upload_paths(path, last_used) VALUES(?, ?)
            ON CONFLICT(path) DO UPDATE SET last_used = excluded.last_used
        """, arguments: [path, now])
    }

    /// Delete history rows beyond `cap` (oldest first). Also unlinks their
    /// thumbnails so the cache directory doesn't grow unbounded.
    private nonisolated static func trimHistory(_ db: GRDB.Database, cap: Int) throws {
        let stale = try Row.fetchAll(db, sql: """
            SELECT id FROM upload_history
             ORDER BY timestamp DESC
             LIMIT -1 OFFSET ?
        """, arguments: [cap])
        for row in stale {
            if let id = row["id"] as String? {
                try db.execute(sql: "DELETE FROM upload_history WHERE id = ?", arguments: [id])
                removeThumbnail(id: id)
            }
        }
    }

    private nonisolated static func trimPaths(_ db: GRDB.Database, cap: Int) throws {
        try db.execute(sql: """
            DELETE FROM upload_paths
             WHERE path NOT IN (
                SELECT path FROM upload_paths
                 ORDER BY last_used DESC
                 LIMIT ?
             )
        """, arguments: [cap])
    }

    // MARK: - Thumbnail file I/O

    private nonisolated static func writeThumbnail(id: String, data: Data) throws {
        let dir = Paths.uploaderCacheDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id).webp")
        try data.write(to: url, options: .atomic)
    }

    private nonisolated static func removeThumbnail(id: String) {
        let url = Paths.uploaderCacheDir.appendingPathComponent("\(id).webp")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Decoder

    private nonisolated static func decode(_ row: Row) -> UploadRecord? {
        guard let id        = row["id"] as String?,
              let filename  = row["filename"] as String?,
              let original  = row["original_name"] as String?,
              let ts        = row["timestamp"] as Int?,
              let origSize  = row["original_size"] as Int?,
              let compSize  = row["compressed_size"] as Int?,
              let width     = row["width"] as Int?,
              let height    = row["height"] as Int?,
              let formatRaw = row["format"] as String?,
              let format    = ImageFormat(rawValue: formatRaw),
              let cdnUrl    = row["cdn_url"] as String?,
              let sha       = row["sha"] as String?
        else { return nil }
        return UploadRecord(
            id: id,
            filename: filename,
            originalName: original,
            timestamp: Date(timeIntervalSince1970: TimeInterval(ts) / 1000),
            originalSize: origSize,
            compressedSize: compSize,
            width: width,
            height: height,
            format: format,
            path: row["path"] as String?,
            cdnUrl: cdnUrl,
            sha: sha,
            githubOwner: row["github_owner"] as String?,
            githubRepo: row["github_repo"] as String?,
            githubBranch: row["github_branch"] as String?
        )
    }
}
