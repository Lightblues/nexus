import Foundation

/// Filesystem layout under ~/.ea/nexus/. Mirrors the Electron PathManager.ts.
enum Paths {
    static var root: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".ea/nexus", isDirectory: true)
    }

    static var configFile: URL    { root.appendingPathComponent("config.json") }
    static var configFileLegacyYAML: URL { root.appendingPathComponent("config.yaml") }
    static var dbFile: URL        { root.appendingPathComponent("nexus.db") }
    static var dataFile: URL      { root.appendingPathComponent("data.json") }
    static var uploaderFile: URL  { root.appendingPathComponent("uploader.json") }
    /// Legacy from Electron build. We no longer use this — AppKit autosaves
    /// window frame to UserDefaults. `cleanupLegacyFiles()` renames it to .bak.
    static var legacyWindowStateFile: URL { root.appendingPathComponent("window-state.json") }

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

    /// Rename obsolete files to *.bak so users can recover them if they want.
    /// Currently:
    ///   - window-state.json (Electron-era; AppKit handles frame autosave now)
    static func cleanupLegacyFiles() {
        let fm = FileManager.default
        let stale = legacyWindowStateFile
        guard fm.fileExists(atPath: stale.path) else { return }
        let bak = stale.appendingPathExtension("bak")
        try? fm.removeItem(at: bak)
        try? fm.moveItem(at: stale, to: bak)
    }
}
