import Foundation
import AppKit
import Combine

/// Pomodoro state machine + 1Hz tick. Mirrors the Electron PomodoroService.ts shape.
/// Owns the only timer; views observe @Published state.
@MainActor
final class PomodoroService: ObservableObject {
    @Published private(set) var state: PomodoroState = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published var draftMetadata: SessionMetadata = .empty   // persisted on next start

    private let repository: PomodoroRepository
    private let config: ConfigService
    private let notifier: NotificationService
    private weak var statusItem: NSStatusItem?

    private var tickTimer: Timer?
    private var autoBreakTask: Task<Void, Never>?
    private var sessionsSinceLongBreak: Int = 0

    init(repository: PomodoroRepository, config: ConfigService, notifier: NotificationService) {
        self.repository = repository
        self.config = config
        self.notifier = notifier
    }

    func attach(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    /// Pull last session metadata + counter from the repository (after refresh).
    /// Falls back to UserDefaults-persisted draft if no historical sessions yet.
    func hydrate() {
        if let persisted = PomodoroRepository.loadPersistedDraft() {
            draftMetadata = persisted
        } else {
            draftMetadata = repository.lastSession
        }
        sessionsSinceLongBreak = repository.sessionsSinceLongBreak
    }

    // MARK: - Public actions

    func start(kind: SessionKind = .work, metadata: SessionMetadata? = nil) {
        cancelAutoBreak()
        let meta = metadata ?? draftMetadata
        draftMetadata = meta
        let total = duration(for: kind)
        state = .running(kind: kind, startedAt: Date(), totalDuration: total)
        remaining = total
        startTickTimer()
        Log.pomodoro.info("start \(kind.rawValue), \(Int(total))s")
    }

    func pause() {
        guard case .running(let kind, let startedAt, let total) = state else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        state = .paused(kind: kind, elapsedAtPause: elapsed, totalDuration: total)
        stopTickTimer()
        updateStatusTitle()
        Log.pomodoro.info("pause")
    }

    func resume() {
        guard case .paused(let kind, let elapsed, let total) = state else { return }
        let virtualStart = Date().addingTimeInterval(-elapsed)
        state = .running(kind: kind, startedAt: virtualStart, totalDuration: total)
        startTickTimer()
        Log.pomodoro.info("resume")
    }

    /// Mark current session done early, persist as a partial completion.
    func finishEarly() async {
        switch state {
        case .running(let kind, let startedAt, _):
            let endedAt = Date()
            await persistSession(kind: kind, startedAt: startedAt, endedAt: endedAt, completedFully: false)
            transitionToFinished(kind: kind, completedFully: false)
        case .paused(let kind, let elapsed, _):
            let endedAt = Date()
            let startedAt = endedAt.addingTimeInterval(-elapsed)
            await persistSession(kind: kind, startedAt: startedAt, endedAt: endedAt, completedFully: false)
            transitionToFinished(kind: kind, completedFully: false)
        default:
            break
        }
    }

    /// Drop the current session without recording it.
    func exit() {
        cancelAutoBreak()
        stopTickTimer()
        state = .idle
        remaining = 0
        updateStatusTitle()
        Log.pomodoro.info("exit")
    }

    func skipBreak() {
        guard case .running(let kind, _, _) = state, kind != .work else { return }
        exit()
    }

    func updateDraftMetadata(_ meta: SessionMetadata) async {
        draftMetadata = meta
        await repository.updateLastSessionMetadata(meta)
    }

    // MARK: - Internals

    private func duration(for kind: SessionKind) -> TimeInterval {
        let cfg = config.config.pomodoro
        switch kind {
        case .work:       return TimeInterval(cfg.workDuration) * 60
        case .shortBreak: return TimeInterval(cfg.shortBreakDuration) * 60
        case .longBreak:  return TimeInterval(cfg.longBreakDuration) * 60
        }
    }

    private func startTickTimer() {
        stopTickTimer()
        tick()  // initial paint
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard case .running(let kind, let startedAt, let total) = state else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remain = max(0, total - elapsed)
        remaining = remain
        updateStatusTitle()
        if remain <= 0 {
            stopTickTimer()
            Task { await self.finalizeOnZero(kind: kind, startedAt: startedAt, total: total) }
        }
    }

    private func finalizeOnZero(kind: SessionKind, startedAt: Date, total: TimeInterval) async {
        let endedAt = startedAt.addingTimeInterval(total)
        await persistSession(kind: kind, startedAt: startedAt, endedAt: endedAt, completedFully: true)

        let title = kind == .work ? "Focus complete" : "Break complete"
        let body  = kind == .work ? "Time for a break." : "Back to work?"
        notifier.notify(title: title, body: body)

        if config.config.pomodoro.confettiOnComplete && kind == .work {
            if let url = URL(string: "raycast://confetti") {
                NSWorkspace.shared.open(url)
            }
        }

        transitionToFinished(kind: kind, completedFully: true)
        scheduleAutoBreakIfNeeded(prevKind: kind)
    }

    private func transitionToFinished(kind: SessionKind, completedFully: Bool) {
        state = .finished(kind: kind, completedFully: completedFully, autoNextAt: nil)
        updateStatusTitle()
    }

    private func scheduleAutoBreakIfNeeded(prevKind: SessionKind) {
        guard prevKind == .work, config.config.pomodoro.autoStartBreak else { return }
        let delay = max(0, config.config.pomodoro.autoStartBreakDelay)
        let nextKind: SessionKind = (sessionsSinceLongBreak + 1) >= config.config.pomodoro.sessionsBeforeLongBreak
            ? .longBreak
            : .shortBreak
        let triggerAt = Date().addingTimeInterval(TimeInterval(delay))
        if case .finished(let kind, let full, _) = state {
            state = .finished(kind: kind, completedFully: full, autoNextAt: triggerAt)
        }
        cancelAutoBreak()
        autoBreakTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                if case .finished = self.state {
                    self.start(kind: nextKind)
                }
            }
        }
    }

    private func cancelAutoBreak() {
        autoBreakTask?.cancel()
        autoBreakTask = nil
    }

    private func persistSession(kind: SessionKind, startedAt: Date, endedAt: Date, completedFully: Bool) async {
        let record = SessionRecord(
            id: UUID(),
            kind: kind,
            startTime: startedAt,
            endTime: endedAt,
            duration: endedAt.timeIntervalSince(startedAt),
            project: draftMetadata.project,
            tags: draftMetadata.tags,
            task: draftMetadata.task,
            completedFully: completedFully
        )
        await repository.insert(record)
        if kind == .work {
            sessionsSinceLongBreak = (sessionsSinceLongBreak + 1) % max(1, config.config.pomodoro.sessionsBeforeLongBreak)
        }
    }

    // MARK: - Status item title

    private func updateStatusTitle() {
        guard let item = statusItem, let button = item.button else { return }
        switch state {
        case .running(let kind, _, _):
            let glyph = kind == .work ? "" : ""
            button.title = " \(glyph)\(Self.formatMMSS(remaining))"
        case .paused:
            button.title = " ⏸ \(Self.formatMMSS(remaining))"
        case .finished:
            button.title = " ✓"
        case .idle:
            button.title = ""
        }
    }

    static func formatMMSS(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
