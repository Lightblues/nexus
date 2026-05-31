import Foundation
import OSLog

/// Two-sink logger: OSLog (visible in Console.app) + file mirror at ~/.ea/nexus/logs/main.log.
/// Mirrors the Electron `electron-log` setup. Rotates the file at 5 MB.
enum Log {
    static let pomodoro = AppLogger(category: "pomodoro")
    static let tracker  = AppLogger(category: "tracker")
    static let uploader = AppLogger(category: "uploader")
    static let palette  = AppLogger(category: "palette")
    static let app      = AppLogger(category: "app")
    static let config   = AppLogger(category: "config")
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
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func write(level: String, category: String, message: String, file: String, line: Int) {
        queue.async { [maxBytes, formatter] in
            let url = Paths.mainLog
            try? FileManager.default.createDirectory(at: Paths.logsDir, withIntermediateDirectories: true)
            FileLogSink.rotateIfNeeded(at: url, maxBytes: maxBytes)
            let ts = formatter.string(from: Date())
            let location = "\(file):\(line)"
            let line = "\(ts) [\(level)] [\(category)] \(message) (\(location))\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static func rotateIfNeeded(at url: URL, maxBytes: UInt64) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size >= maxBytes else { return }
        let backup = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
