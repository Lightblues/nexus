import Foundation

/// Filesystem layout under ~/.ea/nexus/. Mirrors the Electron PathManager.ts.
enum Paths {
    static var root: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ea/nexus", isDirectory: true)
    }

    static var configFile: URL    { root.appendingPathComponent("config.yaml") }
    static var dataFile: URL      { root.appendingPathComponent("data.json") }
    static var uploaderFile: URL  { root.appendingPathComponent("uploader.json") }

    static var archiveDir: URL    { root.appendingPathComponent("archive", isDirectory: true) }
    static var trackerDir: URL    { root.appendingPathComponent("tracker", isDirectory: true) }
    static var uploaderCacheDir: URL {
        root.appendingPathComponent("uploader/cache", isDirectory: true)
    }
    static var logsDir: URL       { root.appendingPathComponent("logs", isDirectory: true) }
    static var mainLog: URL       { logsDir.appendingPathComponent("main.log") }

    static func archiveFile(year: Int) -> URL {
        archiveDir.appendingPathComponent("pomodoro-\(year).json")
    }

    static func trackerFile(date: String) -> URL {
        trackerDir.appendingPathComponent("\(date).json")
    }

    /// Create all known directories. Safe to call repeatedly.
    static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [root, archiveDir, trackerDir, uploaderCacheDir, logsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
