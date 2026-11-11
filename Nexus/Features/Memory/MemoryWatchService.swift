import AppKit
import Combine
import Foundation

/// Watches memory pressure (event-driven, no polling while normal). While pressure is
/// raised it samples every 10 s: notifies with the top apps (inform only, never acts on a
/// process) and writes baton machine events. SADR-021, `.ea/docs/memory.md`.
@MainActor
final class MemoryWatchService: ObservableObject {
    static let sampleInterval: TimeInterval = 10

    @Published private(set) var level: MemoryLevel = .normal

    private let config: ConfigService
    private let notifier: NotificationService
    private let events: MachineEventLog
    private let queue = DispatchQueue(label: "site.easonsi.nexus.memory", qos: .utility)
    private let sampler = MemorySampler()   // used on `queue` only
    private var source: DispatchSourceMemoryPressure?
    private var timer: Timer?
    private var episode = false
    private var gate = NotifyGate()
    private var cancellables: Set<AnyCancellable> = []

    init(config: ConfigService, notifier: NotificationService, events: MachineEventLog = MachineEventLog()) {
        self.config = config
        self.notifier = notifier
        self.events = events
    }

    func bootstrap() {
        apply(config.config.memory)
        config.$config.map(\.memory).removeDuplicates().dropFirst()
            .sink { [weak self] in self?.apply($0) }
            .store(in: &cancellables)
    }

    /// An episode open at quit stays open in the events file: no `pressure_end` is invented.
    func shutdown() { stop() }

    private var settings: MemoryConfig { config.config.memory }

    private func apply(_ cfg: MemoryConfig) {
        gate.minimum = cfg.notifyLevel
        guard cfg.enabled else {
            stop()
            Log.memory.info("disabled by config")
            return
        }
        if cfg.writeEvents {
            let removed = events.prune()
            if !removed.isEmpty { Log.memory.info("pruned \(removed.count) old event files") }
        }
        guard source == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        src.setEventHandler { [weak self] in
            Task { @MainActor in await self?.check() }
        }
        src.activate()
        source = src
        Log.memory.info("watching memory pressure")
        Task { await check() }   // pressure may already be raised at launch
    }

    private func stop() {
        source?.cancel(); source = nil
        timer?.invalidate(); timer = nil
        episode = false
        level = .normal
    }

    /// Read the level and the top processes off the main thread.
    private func read() async -> MemorySnapshot {
        await withCheckedContinuation { cont in
            queue.async { [sampler] in cont.resume(returning: sampler.snapshot()) }
        }
    }

    /// A pressure event or a sample tick: start, continue, or end the episode.
    private func check() async {
        guard settings.enabled, source != nil else { return }
        let snap = await read()
        guard settings.enabled, source != nil else { return }
        level = snap.level
        if snap.level == .normal {
            if episode { finish(snap) }
            return
        }
        if !episode {
            episode = true
            Log.memory.warn("pressure \(snap.level.rawValue): \(MemoryReport.body(snap.processes))")
            write(.pressure, snap)
            startTimer()
        } else {
            write(.sample, snap)
        }
        if gate.shouldNotify(level: snap.level, topApp: MemoryReport.topApps(snap.processes, 1).first?.app, now: Date()) {
            notifier.notify(title: MemoryReport.title(snap.level), body: MemoryReport.body(snap.processes),
                            sound: snap.level == .critical, category: NotificationService.memoryCategory)
        }
    }

    private func finish(_ snap: MemorySnapshot) {
        episode = false
        timer?.invalidate(); timer = nil
        gate.reset(to: .normal)
        write(.pressure_end, snap)
        queue.async { [sampler] in sampler.reset() }
        Log.memory.info("pressure back to normal")
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func write(_ kind: MachineEventLog.Kind, _ snap: MemorySnapshot) {
        guard settings.writeEvents else { return }
        let events = self.events
        queue.async { events.append(kind: kind, snapshot: snap) }
    }

    static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
