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
    private let store: PomodoroStore
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

## Data Layer (`PomodoroStore.swift`)

JSON file at `~/.ea/nexus/data.json`, schema-compatible with Electron (electron-store
just nests user data under a top-level `__internal__`-style key — see migration.md).

```swift
struct PomodoroData: Codable {
    var sessions: [SessionRecord]
    var meta: PomodoroMeta
}

struct SessionRecord: Codable, Identifiable {
    let id: UUID                  // matches Electron uuid v4 strings
    let kind: SessionKind         // "work" | "shortBreak" | "longBreak"
    let startTime: Date           // ISO 8601
    let endTime: Date
    let duration: TimeInterval    // seconds
    var project: String?
    var tags: [String]
    var task: String?
    var completedFully: Bool      // true if reached 0; false if finished early
}

struct PomodoroMeta: Codable {
    var projects: [Project]
    var tags: [String]
    var lastSession: SessionMetadata
}
```

### Archive sweep (port of ADR-004)

At launch:
1. Load `data.json`.
2. Cutoff = `now - 90 days`.
3. Move sessions older than cutoff into `archive/pomodoro-{YYYY}.json`, deduped by ID.
4. Rewrite `data.json` with the trimmed array.

`getAllSessions()` for the activity calendar reads `data.json` + every relevant
`archive/pomodoro-*.json`, merges by ID, returns sorted by `startTime`.

Cache hot for the ActivityCalendar view: load all archives once into a `@Observable`
`SessionHistoryService` and invalidate on new session insertion.

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

Schema in `ConfigSchema.swift` under the `pomodoro.*` block. The `Config.swift`
watcher fires `Config.publisher` → service rebinds durations live. No app
restart for config changes.
