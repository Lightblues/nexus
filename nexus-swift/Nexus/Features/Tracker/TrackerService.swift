import Foundation
import AppKit
import Combine

/// Background window-activity tracker. Polls the active app every N seconds, merges
/// consecutive observations of the same app+file, persists to per-day JSON.
///
/// Runs only when:
///   - config.tracker.enabled = true
///   - Accessibility permission is granted
///   - System idle time < idleThreshold
///
/// Mirrors the Electron TrackerService.ts behavior. See ../tracker.md.
@MainActor
final class TrackerService: ObservableObject {
    enum Status: Equatable {
        case stopped                       // not running (config disabled or starting up)
        case running                       // polling actively
        case waitingForPermission          // AX denied; will retry when granted
        case idle                          // running but user idle, not recording
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastTickAt: Date?
    @Published private(set) var lastError: String?

    private let store: TrackerStore
    private let config: ConfigService
    private let enricher = ContextEnricher()

    private var pollTimer: Timer?
    private var flushTimer: Timer?
    private var configCancellable: AnyCancellable?
    private var permissionCheckTimer: Timer?

    private static let flushInterval: TimeInterval = 5 * 60   // 5 min, matches Electron

    init(store: TrackerStore, config: ConfigService) {
        self.store = store
        self.config = config
    }

    func bootstrap() async {
        await store.bootstrap()
        // React to config changes (poll interval, enabled toggle).
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
        await store.flush()
    }

    // MARK: - Config-driven start/stop

    private func applyConfig(_ cfg: TrackerConfig) {
        if !cfg.enabled {
            stopPolling()
            status = .stopped
            return
        }
        if !Permissions.isAccessibilityTrusted {
            stopPolling()
            status = .waitingForPermission
            schedulePermissionRecheck()
            return
        }
        startPolling(interval: max(1, cfg.pollInterval))
    }

    private func schedulePermissionRecheck() {
        permissionCheckTimer?.invalidate()
        // Poll AX status every 2s while waiting; macOS doesn't notify when grant is given.
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

        let flushTimer = Timer(timeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.store.flush() }
        }
        RunLoop.main.add(flushTimer, forMode: .common)
        self.flushTimer = flushTimer

        status = .running
        Log.tracker.info("started, pollInterval=\(interval)s")
    }

    private func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        flushTimer?.invalidate(); flushTimer = nil
    }

    private func tick() async {
        let cfg = config.config.tracker
        lastTickAt = Date()

        // Idle gate
        let idle = IdleDetector.systemIdleSeconds()
        if idle >= TimeInterval(cfg.idleThreshold) {
            status = .idle
            return
        }
        if status == .idle { status = .running }

        // Probe
        guard let raw = ActiveAppProbe.fetch() else {
            // No focused window — don't extend or finalize; just skip.
            return
        }

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
        if let last = store.lastRecord, Self.isSameActivity(last, candidate) {
            store.extendLastRecord(to: now)
        } else {
            await store.addRecord(candidate)
        }
    }

    /// Two records describe "the same activity" if app + context.file both match.
    /// Matches Electron `isSameActivity`.
    private static func isSameActivity(_ a: WindowActivityRecord, _ b: WindowActivityRecord) -> Bool {
        guard a.app == b.app else { return false }
        return a.context?.file == b.context?.file
    }
}
