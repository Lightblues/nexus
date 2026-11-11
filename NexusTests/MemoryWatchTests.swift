import XCTest
@testable import Nexus

final class MemoryWatchTests: XCTestCase {
    private let gb: UInt64 = 1_073_741_824

    private func p(_ pid: Int32, _ name: String, _ footprint: UInt64, app: String? = nil) -> ProcessUsage {
        ProcessUsage(pid: pid, name: name, app: app, footprint: footprint)
    }

    // MARK: - Top N and formatting

    func testTopIsByFootprintAndCapped() {
        let all = (1...12).map { p(Int32($0), "p\($0)", UInt64($0) * gb) }
        let top = MemoryReport.top(all)
        XCTAssertEqual(top.count, 8)
        XCTAssertEqual(top.first?.name, "p12")
        XCTAssertEqual(top.last?.name, "p5")
        XCTAssertEqual(MemoryReport.top([p(9, "b", gb), p(3, "a", gb)]).map(\.pid), [3, 9], "ties by pid")
    }

    func testNamesComeFromThePathWithoutTheRest() {
        let helper = ProcessUsage.names(fromPath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)")
        XCTAssertEqual(helper.name, "Google Chrome Helper (Renderer)")
        XCTAssertEqual(helper.app, "Google Chrome")
        let daemon = ProcessUsage.names(fromPath: "/System/Library/PrivateFrameworks/CorePDF.framework/XPCServices/CGPDFService.xpc/Contents/MacOS/CGPDFService")
        XCTAssertEqual(daemon.name, "CGPDFService")
        XCTAssertEqual(daemon.app, "CGPDFService")
    }

    func testBodyGroupsByAppAndNamesTheTopThree() {
        let procs = [
            p(1, "CGPDFService", 21 * gb),
            p(2, "Google Chrome", 3 * gb),
            p(3, "Google Chrome Helper (Renderer)", 6 * gb, app: "Google Chrome"),
            p(4, "Code", 5 * gb),
            p(5, "Finder", gb / 4),
        ]
        XCTAssertEqual(MemoryReport.body(procs), "CGPDFService 21 GB · Google Chrome 9.0 GB · Code 5.0 GB")
        XCTAssertEqual(MemoryReport.bytes(850 * 1_048_576), "850 MB")
        XCTAssertEqual(MemoryReport.title(.critical), "Memory pressure critical")
    }

    func testLevelFromSysctl() {
        XCTAssertEqual(MemoryLevel(sysctl: 1), .normal)
        XCTAssertEqual(MemoryLevel(sysctl: 2), .warn)
        XCTAssertEqual(MemoryLevel(sysctl: 4), .critical)
        XCTAssertLessThan(MemoryLevel.warn, .critical)
    }

    // MARK: - Rate limit

    func testAtMostOncePer15Minutes() {
        var gate = NotifyGate()
        let t0 = Date(timeIntervalSince1970: 1_762_850_000)
        XCTAssertTrue(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0))
        XCTAssertFalse(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0 + 10))
        XCTAssertFalse(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0 + 899))
        XCTAssertTrue(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0 + 900))
    }

    func testRiseToCriticalNotifiesOnce() {
        var gate = NotifyGate()
        let t0 = Date(timeIntervalSince1970: 1_762_850_000)
        XCTAssertTrue(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0))
        XCTAssertTrue(gate.shouldNotify(level: .critical, topApp: "Chrome", now: t0 + 10))
        XCTAssertFalse(gate.shouldNotify(level: .critical, topApp: "Chrome", now: t0 + 20))
    }

    func testNewTopAppNotifiesButSwappingBackDoesNot() {
        var gate = NotifyGate()
        let t0 = Date(timeIntervalSince1970: 1_762_850_000)
        XCTAssertTrue(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0))
        XCTAssertTrue(gate.shouldNotify(level: .warn, topApp: "CGPDFService", now: t0 + 10))
        XCTAssertFalse(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0 + 20))
        XCTAssertFalse(gate.shouldNotify(level: .warn, topApp: "CGPDFService", now: t0 + 30))
    }

    func testCriticalOnlySetting() {
        var gate = NotifyGate(minimum: .critical)
        let t0 = Date(timeIntervalSince1970: 1_762_850_000)
        XCTAssertFalse(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0))
        XCTAssertTrue(gate.shouldNotify(level: .critical, topApp: "Chrome", now: t0 + 10))
        XCTAssertFalse(gate.shouldNotify(level: .normal, topApp: "Chrome", now: t0 + 2000))
    }

    func testANewEpisodeCanReachCriticalAgain() {
        var gate = NotifyGate()
        let t0 = Date(timeIntervalSince1970: 1_762_850_000)
        XCTAssertTrue(gate.shouldNotify(level: .critical, topApp: "Chrome", now: t0))
        gate.reset(to: .normal)
        XCTAssertFalse(gate.shouldNotify(level: .warn, topApp: "Chrome", now: t0 + 60), "the 15-min window spans episodes")
        XCTAssertTrue(gate.shouldNotify(level: .critical, topApp: "Chrome", now: t0 + 120))
    }

    // MARK: - JSONL encoder

    /// A line in baton's machine-events contract (baton `.ea/log/2026-11-11-mac-memory.md`, "Data contract").
    private let fixture = #"{"v":1,"t":"2026-11-11T06:19:30.000Z","source":"nexus/1.3.1","kind":"sample","level":"critical","mem":{"total":51539607552,"used":49392123904,"compressed":12884901888,"wired":4294967296},"swap":{"used":10737418240,"total":12884901888},"top":[{"pid":4242,"name":"CGPDFService","footprint":22333829939,"cpu_pct":97.5},{"pid":812,"name":"Google Chrome Helper (Renderer)","footprint":9663676416,"cpu_pct":3}]}"#

    private func snapshot() -> MemorySnapshot {
        MemorySnapshot(
            level: .critical,
            system: SystemMemory(total: 48 * gb, used: 46 * gb, compressed: 12 * gb, wired: 4 * gb, swapUsed: 10 * gb, swapTotal: 12 * gb),
            processes: [
                ProcessUsage(pid: 4242, name: "CGPDFService", footprint: 22_333_829_939, cpuPct: 97.5),
                ProcessUsage(pid: 812, name: "Google Chrome Helper (Renderer)", app: "Google Chrome", footprint: 9 * gb, cpuPct: 3.04),
            ])
    }

    func testLineMatchesTheContractFixture() {
        let t = Date(timeIntervalSince1970: 1_794_377_970)  // 2026-11-11T06:19:30Z
        XCTAssertEqual(MachineEventLog.line(kind: .sample, at: t, source: "nexus/1.3.1", snapshot: snapshot()), fixture)
    }

    func testLineIsValidJSONWithIntegerBytes() throws {
        let line = MachineEventLog.line(kind: .pressure_end, at: Date(), source: "nexus/9", snapshot: snapshot())
        XCTAssertFalse(line.contains("\n"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(obj["kind"] as? String, "pressure_end")
        XCTAssertEqual(Set(obj.keys), ["v", "t", "source", "kind", "level", "mem", "swap", "top"])
        let mem = try XCTUnwrap(obj["mem"] as? [String: Any])
        XCTAssertEqual((mem["total"] as? NSNumber)?.int64Value, Int64(48 * gb))
    }

    func testNamesAreEscaped() throws {
        var snap = snapshot()
        snap.processes = [ProcessUsage(pid: 1, name: "a \"b\" / c", footprint: 1)]
        let line = MachineEventLog.line(kind: .pressure, at: Date(), source: "nexus/9", snapshot: snap)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let top = try XCTUnwrap(obj["top"] as? [[String: Any]])
        XCTAssertEqual(top.first?["name"] as? String, "a \"b\" / c")
    }

    // MARK: - Files

    func testAppendAndPrune() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-events-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = MachineEventLog(dir: dir, source: "nexus/test")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(log.prune(calendar: cal), [], "a missing directory is not created")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))

        let now = Date()
        log.append(kind: .pressure, snapshot: snapshot(), at: now)
        log.append(kind: .sample, snapshot: snapshot(), at: now)
        let today = dir.appendingPathComponent(MachineEventLog.fileName(for: now))
        XCTAssertEqual(try String(contentsOf: today).split(separator: "\n").count, 2)

        for name in ["2020-01-01.jsonl", "2020-01-02.jsonl", "notes.txt"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        XCTAssertEqual(log.prune(now: now, calendar: cal), ["2020-01-01.jsonl", "2020-01-02.jsonl"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: today.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
    }

    func testConfigDefaults() throws {
        let cfg = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8)).memory
        XCTAssertTrue(cfg.enabled)
        XCTAssertEqual(cfg.notifyLevel, .warn)
        XCTAssertTrue(cfg.writeEvents)
        let odd = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"memory":{"notifyLevel":"normal","writeEvents":false}}"#.utf8)).memory
        XCTAssertEqual(odd.notifyLevel, .warn)
        XCTAssertFalse(odd.writeEvents)
    }
}
