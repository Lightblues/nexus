import Foundation

/// Writes baton's machine events (`~/.baton/machine-events/<YYYY-MM-DD>.jsonl`, the format
/// baton defines in `.ea/docs/machines.md`, "Machine events"). Optional on both sides:
/// baton reads the file if it is there; nexus never needs baton.
struct MachineEventLog {
    enum Kind: String { case pressure, sample, pressure_end }

    static var defaultDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".baton/machine-events", isDirectory: true)
    }

    let dir: URL
    let source: String

    init(dir: URL = MachineEventLog.defaultDir, source: String = MachineEventLog.source()) {
        self.dir = dir; self.source = source
    }

    static func source(bundle: Bundle = .main) -> String {
        "nexus/\(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")"
    }

    /// One JSON object, keys in the contract's order, integer byte counts.
    static func line(kind: Kind, at t: Date, source: String, snapshot s: MemorySnapshot) -> String {
        let top = s.processes.map { p in
            "{\"pid\":\(p.pid),\"name\":\(quote(p.name)),\"footprint\":\(p.footprint),\"cpu_pct\":\(number(p.cpuPct))}"
        }.joined(separator: ",")
        let m = s.system
        return "{\"v\":1,\"t\":\(quote(timestamp(t))),\"source\":\(quote(source)),\"kind\":\"\(kind.rawValue)\","
            + "\"level\":\"\(s.level.rawValue)\","
            + "\"mem\":{\"total\":\(m.total),\"used\":\(m.used),\"compressed\":\(m.compressed),\"wired\":\(m.wired)},"
            + "\"swap\":{\"used\":\(m.swapUsed),\"total\":\(m.swapTotal)},"
            + "\"top\":[\(top)]}"
    }

    /// ISO 8601 in UTC with milliseconds, so lines sort and compare as strings (baton's cursor).
    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// Local calendar day: the file the line goes to.
    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.jsonl", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func append(kind: Kind, snapshot: MemorySnapshot, at t: Date = Date()) {
        let data = Data((Self.line(kind: kind, at: t, source: source, snapshot: snapshot) + "\n").utf8)
        let url = dir.appendingPathComponent(Self.fileName(for: t))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url)
            }
        } catch {
            Log.memory.warn("machine event write failed: \(error)")
        }
    }

    /// Delete day files older than `days` (by the date in their name). Never creates the directory.
    @discardableResult
    func prune(olderThan days: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        let parse = DateFormatter()
        parse.calendar = calendar; parse.timeZone = calendar.timeZone
        parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = "yyyy-MM-dd"
        var removed: [String] = []
        for name in names where name.hasSuffix(".jsonl") {
            guard let day = parse.date(from: String(name.dropLast(6))), day < cutoff else { continue }
            if (try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))) != nil { removed.append(name) }
        }
        return removed.sorted()
    }

    private static func quote(_ s: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? String(decoding: encoder.encode(s), as: UTF8.self)) ?? "\"\""
    }

    private static func number(_ d: Double) -> String {
        let r = (d * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}
