import AppKit
import Combine
import GRDB
import NexusSync

/// Owns the app's one `SyncEngine` and decides when it runs: at launch, every 5 minutes,
/// after the Mac wakes, and 5 s after the last pomodoro or settings edit. Tracker records,
/// which change every poll, ride the timer. One sync at a time; failures back off and
/// show in the status. With sync off there is no engine and no network.
@MainActor
final class SyncCoordinator: ObservableObject {
    static let interval: TimeInterval = 300
    static let editDelay: TimeInterval = 5
    static let wakeDelay: TimeInterval = 10

    @Published private(set) var connection: SyncConnection
    @Published private(set) var isSyncing = false
    @Published private(set) var lastAttempt: Date?
    /// The last attempt's report; nil when it failed.
    @Published private(set) var lastReport: SyncReport?
    /// Why the last attempt failed, or which items the server refused.
    @Published private(set) var lastError: String?

    private let database: Database
    private let config: ConfigService
    private let onPulled: () async -> Void
    private var engine: SyncEngine?
    private var pending: Task<Void, Never>?
    private var failures = 0
    private var nextAllowed = Date.distantPast
    private var rerun = false
    private var started = false
    private var observation: AnyDatabaseCancellable?
    private var cancellables: Set<AnyCancellable> = []

    init(database: Database, config: ConfigService, onPulled: @escaping () async -> Void) {
        self.database = database
        self.config = config
        self.onPulled = onPulled
        self.connection = SyncConnection.load()
    }

    /// Call once after bootstrap, so the first sync sees loaded config and repositories.
    func start() {
        guard !started else { return }
        started = true
        let edits = DatabaseRegionObservation(tracking: [
            Table("pomodoro_sessions"), Table("pomodoro_session_tags"),
            Table("pomodoro_projects"), Table("pomodoro_tag_catalog"),
        ])
        observation = edits.start(in: database.queue,
                                  onError: { Log.sync.warn("edit observation failed: \($0)") },
                                  onChange: { _ in Task { @MainActor [weak self] in self?.localEdit() } })
        config.$config.dropFirst().removeDuplicates()
            .sink { [weak self] _ in self?.localEdit() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.schedule(in: Self.wakeDelay) }
            .store(in: &cancellables)
        configure()
    }

    /// Save a new connection to `sync.json` and restart sync with it.
    func update(_ new: SyncConnection) throws {
        guard new != connection else { return }
        try new.save()
        connection = new
        configure()
    }

    /// Sync immediately, ignoring the backoff.
    func syncNow() {
        guard engine != nil else { return }
        pending?.cancel()
        Task { await run() }
    }

    // MARK: - Scheduling

    private func configure() {
        pending?.cancel()
        failures = 0
        nextAllowed = .distantPast
        lastError = nil
        guard started, connection.isActive, let url = connection.serverURL else { engine = nil; return }
        engine = SyncEngine(db: database.queue, api: SyncClient(baseURL: url, key: connection.key),
                            settings: ConfigSettingsStore(config: config))
        schedule(in: 0)
    }

    private func localEdit() {
        guard engine != nil else { return }
        // A sync's own writes land here too; one follow-up sync settles them.
        if isSyncing { rerun = true } else { schedule(in: Self.editDelay) }
    }

    /// Replace the pending sync with one `delay` seconds out (or later, while backing off).
    private func schedule(in delay: TimeInterval) {
        guard engine != nil else { return }
        pending?.cancel()
        let wait = max(delay, nextAllowed.timeIntervalSinceNow)
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(wait, 0) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // A detached run, so rescheduling (which cancels `pending`) never cancels a sync in flight.
            Task { await self.run() }
        }
    }

    private func run() async {
        guard let engine else { return }
        if isSyncing { rerun = true; return }
        isSyncing = true
        lastAttempt = Date()
        let result: Result<SyncReport, Error>
        do { result = .success(try await engine.sync()) } catch { result = .failure(error) }
        isSyncing = false
        // The connection changed meanwhile: the new engine owns the status and the schedule.
        guard self.engine === engine else {
            if rerun { rerun = false; schedule(in: 0) }
            return
        }
        switch result {
        case .success(let report):
            failures = 0
            nextAllowed = .distantPast
            lastReport = report
            lastError = report.failed.isEmpty ? nil : "\(report.failed.count) item(s) refused: \(report.failed.prefix(3).joined(separator: ", "))"
            Log.sync.info("sync ok: pushed \(report.pushed), pulled \(report.pulled), stale \(report.stale), failed \(report.failed.count)")
            if !report.failed.isEmpty { Log.sync.warn("refused: \(report.failed.joined(separator: "; "))") }
            if report.pulled + report.stale > 0 { await onPulled() }
        case .failure(let error):
            failures += 1
            let backoff = min(30 * pow(2, Double(failures - 1)), 1800)
            nextAllowed = Date().addingTimeInterval(backoff)
            lastReport = nil
            lastError = Self.describe(error)
            Log.sync.warn("sync failed (\(failures)x, retry in \(Int(backoff))s): \(lastError ?? "")")
        }
        if rerun { rerun = false; schedule(in: Self.editDelay) } else { schedule(in: failures > 0 ? 0 : Self.interval) }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case SyncError.http(401, _): return "Unauthorized: check the key"
        case SyncError.http(403, _): return "Forbidden: this is not the sync key"
        case SyncError.http(let status, let code): return "HTTP \(status)" + (code.map { " (\($0))" } ?? "")
        case SyncError.badResponse: return "Unexpected server response"
        case let e as URLError: return e.localizedDescription
        default: return String(describing: error)
        }
    }
}
