# Pomodoro

Pomodoro timer with focus + short/long-break cycle, persisted session log,
inline edit modal. State machine, popover UI, config schema below.

## State Machine

```swift
enum PomodoroState: Equatable {
    case idle
    case running(kind: SessionKind, startedAt: Date, duration: TimeInterval)
    case paused(kind: SessionKind, elapsed: TimeInterval, totalDuration: TimeInterval)
    case finished(kind: SessionKind, autoNextAt: Date?)
}

enum SessionKind { case work, shortBreak, longBreak }
```

Same transitions as Electron version (`Idle → Running → Paused → Finished → (auto) break`).
Auto-start break uses a `Task.sleep(for: cfg.autoStartBreakDelay.seconds)` that the
service can cancel on user action.

## Service (`PomodoroService.swift`)

```swift
@Observable @MainActor
final class PomodoroService {
    private(set) var state: PomodoroState = .idle
    private(set) var remaining: TimeInterval = 0
    private(set) var todayCount: Int = 0
    private(set) var todayDuration: TimeInterval = 0
    private(set) var lastSession: SessionMetadata = .empty

    private var tickTimer: Timer?
    private var autoBreakTask: Task<Void, Never>?
    private let repository: PomodoroRepository
    private let config: ConfigService
    private let notifier: NotificationService
    private let tray: StatusItemController
    
    func start(metadata: SessionMetadata, kind: SessionKind = .work) { ... }
    func pause() { ... }
    func resume() { ... }
    func finishEarly() async { ... }
    func exit() { ... }
    func skipBreak() { ... }
}
```

### Tick

A 1Hz `Timer` (RunLoop common modes — must keep firing while menus are tracking).
On each tick:
1. Update `remaining`.
2. Push attributed string to status item title (only when state is `.running` and
   `cfg.showTitleCountdown == true`).
3. If `remaining <= 0`: transition to `.finished`, persist session via store, fire
   notification, schedule autoBreakTask if configured.

The status item title write is the **hot path** — keep it allocation-free:
```swift
// Pre-format once per second; status bar accepts attributed strings.
tray.button?.title = " \(formatMMSS(remaining))"
```

No SwiftUI re-render is triggered for the tray title — it's an AppKit property.
The popover view binds to `@Observable remaining` and re-renders only while open.

## Data Layer (`PomodoroRepository.swift`)

SQLite tables in nexus.db: `pomodoro_sessions` (id, kind, start and end time in unix
seconds, duration, project, task, completed_fully), `pomodoro_session_tags`,
`pomodoro_projects` (name, color, created_at), and `pomodoro_tag_catalog`. All of them sync
(`sync.md`). There is no archive sweep: the database keeps every session, and the stats
views query by date range. A new Mac starts with empty catalogs and gets the projects and
tags from the server on its first sync.

## Popover UI (`Views/PomodoroPopoverView.swift`)

Frame: 320 × 400. Layout:

```
[← Back]  [Focus]  [#7]
┌─────────────────────────┐
│  7 sessions  │  2h 31m  │     ← clickable → openMain(.stats)
└─────────────────────────┘
      ┌──────────┐
      │  --:--   │             ← Canvas progress ring
      └──────────┘
┌─────────────────────────┐
│ projectName · tag1, tag2│     ← clickable → EditSessionModal
└─────────────────────────┘
      [Start Focus]
```

Implemented with SwiftUI `VStack` + `Canvas` for the ring. Ring redraws on every tick
but only while the popover is open — when hidden, the SwiftUI body is not invoked.

### EditSessionModal

A SwiftUI sheet, not a separate window. Same shared modal for idle and running/paused
states (ADR-007 preserved). Esc dismiss is built into `.sheet` semantics.

Project selector: `Menu` with config projects + an "+ New" item that swaps to a
`TextField`. Tags: `ScrollView` with chip rendering + `TextField("Add tag")`. Task: a
single-line `TextField`.

`maxHeight: 100` on the tags scroll view (preserves the 100px scroll cap from
Electron).

## Stats UI

### Activity Calendar (`Views/ActivityCalendar.swift`)

Replaces `react-activity-calendar`. Custom SwiftUI view backed by `Canvas`:
- 53 weeks × 7 days grid, 11 px cells with 2 px gap (matches the Electron sizing).
- Per-day count → 5-bucket color scale (transparent → primary).
- Hover tooltip via `.onHover` + position tracking, shown as a SwiftUI overlay.
- Reads from `SessionHistoryService` (active + archived).

### Weekly Bar Chart (`Views/StatsView.swift`)

Swift `Charts` framework — replaces Recharts:
```swift
Chart(weekData) { day in
    BarMark(x: .value("Day", day.label), y: .value("Hours", day.hours))
        .foregroundStyle(by: .value("Kind", day.kind))
}
.frame(height: 200)
```

### Daily Timeline

A custom `Canvas` 24h horizontal bar — work=accent, break=green, tooltip on hover.
Recharts doesn't have an out-of-the-box equivalent and the Electron version is
already custom; mirror that here.

### Session List

`List(sessionsForDay) { session in SessionRow(session) }`. `SessionRow` opens
`EditSessionSheet` for inline editing. Saves go through `PomodoroService.update(_:)`
which writes to the store and updates `SessionHistoryService`.

## Commands (registered with CommandRegistry)

Same set as Electron palette — see `palette.md` for the table:
- `pomodoro.toggle`
- `pomodoro.start`
- `pomodoro.pause`
- `pomodoro.resume`
- `pomodoro.finishEarly`
- `pomodoro.exit`

Subtitles are dynamic via closures that read live state. Implementation mirrors the TS
version 1:1 — the registry shape is the same.

## Notifications

`UNUserNotificationCenter` with a single category `pomodoro.completion`. Body says
"Focus complete — break starts in N seconds" or "Break done — back to work?" depending
on kind. Sound: default. No actions in v1 (Electron version has none either).

`confettiOnComplete` (config) fires a Raycast confetti deeplink the same way the
Electron build does — open `raycast://confetti`.

## Config

`pomodoro.*` in `AppConfig` (stored in nexus.db, `architecture.md`). Services subscribe to
`ConfigService.$config`, so a change from Settings, sync, or `nexus config set` applies
live.

When a focus session runs to zero: `confettiOnComplete` opens Raycast's confetti without
activating Raycast, and `showPopoverOnComplete` shows the status-item popover, which does
not activate Nexus either. Neither applies to breaks.
