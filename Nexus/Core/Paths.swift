import Foundation

/// Standard macOS data layout, keyed by bundle identifier:
///
///   ~/Library/Application Support/site.easonsi.nexus/   user-critical: nexus.db (data and settings), sync.json
///   ~/Library/Caches/site.easonsi.nexus/                regenerable: thumbnails
///   ~/Library/Logs/site.easonsi.nexus/                  append-only: main.log
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

    /// Settings before they moved into nexus.db (v1.3.2); imported once, then renamed `config.json.imported`.
    static var legacyConfigFile: URL { supportDir.appendingPathComponent("config.json") }
    static var dbFile: URL     { supportDir.appendingPathComponent("nexus.db") }
    /// Sync connection (enabled, server, key). Local to this Mac, never synced.
    static var syncFile: URL   { supportDir.appendingPathComponent("sync.json") }

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
