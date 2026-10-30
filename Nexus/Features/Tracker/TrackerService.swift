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
    /// The system Accessibility prompt is raised once per launch; macOS limits how often it shows.
    private var promptedAccessibility = false
    /// Notifies once per launch when the tracker is still waiting for Accessibility, so a lost grant cannot go unnoticed for months.
    private var waitingNoticeTask: Task<Void, Never>?
    private let notifier: NotificationService?

    /// Frontmost while the screen is locked or the screen saver runs; never recorded as activity.
    nonisolated static let lockScreenBundleIds: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]

    init(repository: TrackerRepository, config: ConfigService, notifier: NotificationService? = nil) {
        self.repository = repository
        self.config = config
        self.notifier = notifier
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
            waitingNoticeTask?.cancel(); waitingNoticeTask = nil
            stopPolling()
            status = .stopped
            Log.tracker.info("disabled by config")
            return
        }
        if !Permissions.isAccessibilityTrusted {
            stopPolling()
            status = .waitingForPermission
            Log.tracker.warn("waiting for Accessibility permission — grant in System Settings → Privacy & Security → Accessibility")
            if !promptedAccessibility {
                promptedAccessibility = true
                Permissions.promptAccessibility()
                waitingNoticeTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(600))
                    guard !Task.isCancelled, let self, self.status == .waitingForPermission else { return }
                    self.notifier?.notify(title: "Nexus is not tracking time",
                                          body: "Accessibility access is off. Grant it in System Settings → Privacy & Security → Accessibility.")
                }
            }
            schedulePermissionRecheck()
            return
        }
        waitingNoticeTask?.cancel(); waitingNoticeTask = nil
        startPolling(interval: max(1, cfg.pollInterval))
    }

    private func schedulePermissionRecheck() {
        permissionCheckTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            let weakSelf = self
            Task { @MainActor in
                guard let s = weakSelf else { return }
                if Permissions.isAccessibilityTrusted {
                    s.permissionCheckTimer?.invalidate()
                    s.permissionCheckTimer = nil
                    s.applyConfig(s.config.config.tracker)
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
            let weakSelf = self
            Task { @MainActor in await weakSelf?.tick() }
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
        if let bid = raw.bundleId, Self.lockScreenBundleIds.contains(bid) {
            status = .idle
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
        if let last = repository.lastRecord, Self.canExtend(last, with: candidate, at: now, pollInterval: cfg.pollInterval) {
            await repository.extendLastRecord(to: now)
        } else {
            await repository.insert(candidate)
        }
    }

    /// Extend the last record only for the same activity seen within a few polls. A longer gap is
    /// idle time, sleep, or the lock screen, and must not be counted.
    nonisolated static func canExtend(_ last: WindowActivityRecord, with candidate: WindowActivityRecord,
                                      at now: Date, pollInterval: Int) -> Bool {
        isSameActivity(last, candidate) && now.timeIntervalSince(last.endTime) <= maxGap(pollInterval: pollInterval)
    }

    nonisolated static func maxGap(pollInterval: Int) -> TimeInterval {
        max(15, TimeInterval(3 * max(1, pollInterval)))
    }

    /// Two records describe "the same activity" if app + context.file both match.
    nonisolated static func isSameActivity(_ a: WindowActivityRecord, _ b: WindowActivityRecord) -> Bool {
        guard a.app == b.app else { return false }
        return a.context?.file == b.context?.file
    }
}
