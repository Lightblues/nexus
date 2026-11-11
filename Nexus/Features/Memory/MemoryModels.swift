import Foundation

/// Memory-pressure level, as baton's machine-events contract names it.
enum MemoryLevel: String, Codable, Comparable {
    case normal, warn, critical

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warn, 4 critical.
    init(sysctl value: Int32) {
        switch value {
        case 4: self = .critical
        case 2: self = .warn
        default: self = .normal
        }
    }

    private var rank: Int { self == .normal ? 0 : self == .warn ? 1 : 2 }
    static func < (a: MemoryLevel, b: MemoryLevel) -> Bool { a.rank < b.rank }
}

/// One process at sample time. `name` is the executable name; `app` the outermost `.app`
/// bundle it lives in (Chrome's helpers group under "Google Chrome"), else the name.
/// Never arguments or other paths.
struct ProcessUsage: Equatable {
    var pid: Int32
    var name: String
    var app: String
    var footprint: UInt64
    var cpuPct: Double

    init(pid: Int32, name: String, app: String? = nil, footprint: UInt64, cpuPct: Double = 0) {
        self.pid = pid; self.name = name; self.app = app ?? name; self.footprint = footprint; self.cpuPct = cpuPct
    }

    /// Display name and group key from an executable path; the path itself is dropped.
    static func names(fromPath path: String) -> (name: String, app: String) {
        let parts = path.split(separator: "/").map(String.init)
        let name = parts.last ?? path
        let app = parts.first(where: { $0.hasSuffix(".app") }).map { String($0.dropLast(4)) } ?? name
        return (name, app)
    }
}

struct SystemMemory: Equatable {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var compressed: UInt64 = 0
    var wired: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
}

struct MemorySnapshot {
    var level: MemoryLevel
    var system: SystemMemory
    var processes: [ProcessUsage]
}

enum MemoryReport {
    /// The `n` largest processes by footprint; ties broken by pid for a stable order.
    static func top(_ processes: [ProcessUsage], _ n: Int = 8) -> [ProcessUsage] {
        Array(processes.sorted { $0.footprint != $1.footprint ? $0.footprint > $1.footprint : $0.pid < $1.pid }.prefix(n))
    }

    /// Footprint summed per app, largest first: what the notification names.
    static func topApps(_ processes: [ProcessUsage], _ n: Int = 3) -> [(app: String, footprint: UInt64)] {
        var sums: [String: UInt64] = [:]
        for p in processes { sums[p.app, default: 0] += p.footprint }
        return Array(sums.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(n).map { (app: $0.key, footprint: $0.value) })
    }

    /// `21 GB`, `9.4 GB`, `850 MB` (binary units, as Activity Monitor shows them).
    static func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return "\(Int((Double(b) / 1_048_576).rounded())) MB"
    }

    /// `CGPDFService 21 GB · Google Chrome 9.4 GB · Code 5.0 GB`
    static func body(_ processes: [ProcessUsage]) -> String {
        topApps(processes).map { "\($0.app) \(bytes($0.footprint))" }.joined(separator: " · ")
    }

    static func title(_ level: MemoryLevel) -> String {
        level == .critical ? "Memory pressure critical" : "Memory pressure warning"
    }
}

/// When to notify: at most once per 15 min, except when the level rises to critical or a
/// new app becomes the top one (an app already named in the window does not count again,
/// so two apps trading places do not notify every sample).
struct NotifyGate {
    var minimum: MemoryLevel = .warn
    var interval: TimeInterval = 15 * 60
    private(set) var lastAt: Date?
    private(set) var lastLevel: MemoryLevel = .normal
    private var namedAt: [String: Date] = [:]

    init(minimum: MemoryLevel = .warn, interval: TimeInterval = 15 * 60) {
        self.minimum = minimum; self.interval = interval
    }

    /// Decide for this reading; records the notification when it returns true.
    mutating func shouldNotify(level: MemoryLevel, topApp: String?, now: Date) -> Bool {
        guard level >= minimum, level != .normal else { return false }
        let fire: Bool
        if let last = lastAt {
            let toCritical = level == .critical && lastLevel != .critical
            let newTop = topApp.map { name in namedAt[name].map { now.timeIntervalSince($0) >= interval } ?? true } ?? false
            fire = toCritical || newTop || now.timeIntervalSince(last) >= interval
        } else {
            fire = true
        }
        guard fire else { return false }
        lastAt = now
        lastLevel = level
        if let topApp { namedAt[topApp] = now }
        return true
    }

    /// A return to normal ends the episode's critical state; the 15-min window still holds.
    mutating func reset(to level: MemoryLevel) {
        if level == .normal { lastLevel = .normal }
    }
}
