import Foundation
import OSLog

/// Two-sink logger: OSLog (visible in Console.app + `log show`) + file mirror at
/// `~/Library/Logs/site.easonsi.nexus/main.log`.
///
/// - File sink rotates at 5 MB, keeping the 4 most recent generations
///   (`main.log.1`..`main.log.4`) plus the live file — ~25 MB total cap.
/// - Each launch writes a banner line so eyeballing the file for "what
///   happened in this session" is straightforward (`grep '====='`).
/// - Source location is rendered as `<basename>:<line>` rather than the full
///   `Nexus/Features/.../File.swift` path that `#fileID` defaults to.
enum Log {
    static let pomodoro = AppLogger(category: "pomodoro")
    static let tracker  = AppLogger(category: "tracker")
    static let uploader = AppLogger(category: "uploader")
    static let palette  = AppLogger(category: "palette")
    static let app      = AppLogger(category: "app")
    static let config   = AppLogger(category: "config")

    /// Write a one-line "session start" banner. Called from AppDelegate at
    /// `applicationDidFinishLaunching`. Goes only to the file sink (OSLog
    /// already records process start with its own metadata).
    static func writeLaunchBanner() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let pid = ProcessInfo.processInfo.processIdentifier
        FileLogSink.shared.writeBanner(
            "===== Launched Nexus v\(v) (pid=\(pid)) ====="
        )
    }
}

struct AppLogger {
    private static let subsystem = "site.easonsi.nexus"
    private let osLogger: Logger
    let category: String

    init(category: String) {
        self.category = category
        self.osLogger = Logger(subsystem: AppLogger.subsystem, category: category)
    }

    func info(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        let msg = message()
        osLogger.info("\(msg, privacy: .public)")
        FileLogSink.shared.write(level: "INFO", category: category, message: msg, file: file, line: line)
    }
    func warn(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        let msg = message()
        osLogger.warning("\(msg, privacy: .public)")
        FileLogSink.shared.write(level: "WARN", category: category, message: msg, file: file, line: line)
    }
    func error(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        let msg = message()
        osLogger.error("\(msg, privacy: .public)")
        FileLogSink.shared.write(level: "ERROR", category: category, message: msg, file: file, line: line)
    }
    func debug(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        let msg = message()
        osLogger.debug("\(msg, privacy: .public)")
        FileLogSink.shared.write(level: "DEBUG", category: category, message: msg, file: file, line: line)
    }
}

private final class FileLogSink: @unchecked Sendable {
    static let shared = FileLogSink()
    private let queue = DispatchQueue(label: "site.easonsi.nexus.filelog", qos: .utility)
    private let maxBytes: UInt64 = 5 * 1024 * 1024
    private let maxGenerations = 4   // .1 .. .4 plus live → 5 files, ~25 MB
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func write(level: String, category: String, message: String, file: String, line: Int) {
        queue.async { [maxBytes, maxGenerations, formatter] in
            let url = Paths.mainLog
            try? FileManager.default.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)
            FileLogSink.rotateIfNeeded(at: url, maxBytes: maxBytes, maxGenerations: maxGenerations)
            let ts = formatter.string(from: Date())
            let location = "\(FileLogSink.shortName(file)):\(line)"
            let line = "\(ts) [\(level)] [\(category)] \(message) (\(location))\n"
            FileLogSink.append(line, to: url)
        }
    }

    /// Plain banner without the [LEVEL][category] formatting.
    func writeBanner(_ banner: String) {
        queue.async { [maxBytes, maxGenerations, formatter] in
            let url = Paths.mainLog
            try? FileManager.default.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)
            FileLogSink.rotateIfNeeded(at: url, maxBytes: maxBytes, maxGenerations: maxGenerations)
            let ts = formatter.string(from: Date())
            let line = "\n\(ts) \(banner)\n"
            FileLogSink.append(line, to: url)
        }
    }

    /// Strip the leading `Nexus/Features/.../` segments from `#fileID`, keeping
    /// only the basename. `#fileID` looks like "Nexus/Features/Pomodoro/Foo.swift";
    /// we want just "Foo.swift" — the line number plus that is enough to jump.
    private static func shortName(_ fileID: String) -> String {
        if let slash = fileID.lastIndex(of: "/") {
            return String(fileID[fileID.index(after: slash)...])
        }
        return fileID
    }

    private static func append(_ string: String, to url: URL) {
        guard let data = string.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Rotate `main.log` → `main.log.1`, shifting older generations down. The
    /// oldest generation past `maxGenerations` is deleted. Called inline before
    /// every write — cheap when no rotation is needed (single stat call).
    private static func rotateIfNeeded(at url: URL, maxBytes: UInt64, maxGenerations: Int) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size >= maxBytes else { return }
        let fm = FileManager.default
        // Drop the oldest, then shift each older generation up by one.
        let oldest = url.appendingPathExtension("\(maxGenerations)")
        try? fm.removeItem(at: oldest)
        for n in stride(from: maxGenerations - 1, through: 1, by: -1) {
            let src = url.appendingPathExtension("\(n)")
            let dst = url.appendingPathExtension("\(n + 1)")
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dst)
            }
        }
        // Live file → .1
        try? fm.moveItem(at: url, to: url.appendingPathExtension("1"))
    }
}
