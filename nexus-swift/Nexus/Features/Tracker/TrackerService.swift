import Foundation
import AppKit
import Combine

/// Background window-activity tracker. Polls the active app every N seconds, merges
/// consecutive observations of the same app+file, persists rows to SQLite.
///
/// Runs only when:
///   - config.tracker.enabled = true
///   - Accessibility permission is granted
///   - System idle time < idleThreshold
@MainActor
final class TrackerService: ObservableObject {
    enum Status: Equatable {
        case stopped
        case running
        case waitingForPermission
        case idle
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastTickAt: Date?

    private let repository: TrackerRepository
    private let config: ConfigService
    private let enricher = ContextEnricher()

    private var pollTimer: Timer?
    private var configCancellable: AnyCancellable?
    private var permissionCheckTimer: Timer?

    init(repository: TrackerRepository, config: ConfigService) {
        self.repository = repository
        self.config = config
    }

    func bootstrap() async {
        await repository.bootstrap()
        configCancellable = config.$config
            .map(\.tracker)
            .removeDuplicates()
            .sink { [weak self] tracker in
                Task { @MainActor in self?.applyConfig(tracker) }
            }
        applyConfig(config.config.tracker)
    }

    func shutdown() async {
        stopPolling()
        // SQLite is durable per commit — no flush needed.
    }

    // MARK: - Config-driven start/stop

    private func applyConfig(_ cfg: TrackerConfig) {
        if !cfg.enabled {
            stopPolling()
            status = .stopped
            Log.tracker.info("disabled by config")
            return
        }
        if !Permissions.isAccessibilityTrusted {
            stopPolling()
            status = .waitingForPermission
            Log.tracker.warn("waiting for Accessibility permission — grant in System Settings → Privacy & Security → Accessibility")
            schedulePermissionRecheck()
            return
        }
        startPolling(interval: max(1, cfg.pollInterval))
    }

    private func schedulePermissionRecheck() {
        permissionCheckTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if Permissions.isAccessibilityTrusted {
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    self.applyConfig(self.config.config.tracker)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionCheckTimer = timer
    }

    // MARK: - Poll loop

    private func startPolling(interval: Int) {
        stopPolling()
        let pollTimer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        self.pollTimer = pollTimer

        status = .running
        Log.tracker.info("started, pollInterval=\(interval)s")
    }

    private func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
    }

    private func tick() async {
        let cfg = config.config.tracker
        lastTickAt = Date()

        let idle = IdleDetector.systemIdleSeconds()
        if idle >= TimeInterval(cfg.idleThreshold) {
            status = .idle
            return
        }
        if status == .idle { status = .running }

        guard let raw = ActiveAppProbe.fetch() else { return }

        let (probe, context) = enricher.enrich(raw, config: cfg)
        let now = Date()
        let candidate = WindowActivityRecord(
            startTime: now,
            endTime: now,
            duration: 0,
            app: probe.app,
            bundleId: probe.bundleId,
            title: cfg.recordTitle ? probe.title : nil,
            context: context
        )

        // Merge with last record if same activity
        if let last = repository.lastRecord, Self.isSameActivity(last, candidate) {
            await repository.extendLastRecord(to: now)
        } else {
            await repository.insert(candidate)
        }
    }

    /// Two records describe "the same activity" if app + context.file both match.
    private static func isSameActivity(_ a: WindowActivityRecord, _ b: WindowActivityRecord) -> Bool {
        guard a.app == b.app else { return false }
        return a.context?.file == b.context?.file
    }
}
