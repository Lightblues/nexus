import Foundation

/// Standard macOS data layout, keyed by bundle identifier:
///
///   ~/Library/Application Support/site.easonsi.nexus/   user-critical: config + db
///   ~/Library/Caches/site.easonsi.nexus/                regenerable: thumbnails
///   ~/Library/Logs/site.easonsi.nexus/                  append-only: main.log
///
/// (Pre-v1.2.0 builds used ~/.ea/nexus/ for everything; the migration script
/// `scripts/migrate-data-v1.2.0.sh` moves the user-critical files over and
/// archives the rest to `~/.ea/nexus.pre-v1.2.0-bak-*`.)
enum Paths {
    static let bundleID = "site.easonsi.nexus"

    // MARK: - Roots

    /// `~/Library/Application Support/site.easonsi.nexus/`
    static var supportDir: URL {
        let lib = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// `~/Library/Caches/site.easonsi.nexus/`
    static var cachesDir: URL {
        let lib = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// `~/Library/Logs/site.easonsi.nexus/`
    static var logsDir: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // MARK: - User-critical (Application Support)

    static var configFile: URL { supportDir.appendingPathComponent("config.json") }
    static var dbFile: URL     { supportDir.appendingPathComponent("nexus.db") }

    // MARK: - Regenerable (Caches)

    static var uploaderCacheDir: URL { cachesDir.appendingPathComponent("uploader-thumbnails", isDirectory: true) }

    // MARK: - Logs

    static var mainLog: URL { logsDir.appendingPathComponent("main.log") }

    // MARK: - Setup

    /// Create all directories the app writes into. Safe to call repeatedly.
    static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [supportDir, cachesDir, logsDir, uploaderCacheDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
