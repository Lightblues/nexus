# Architecture

## Overview

Single-process macOS app. The Swift rewrite replaces the predecessor Electron
build's main + 4 helper processes with one binary that hosts: status item,
popover, main window, palette panel, and all background services. (Electron-era
files referenced below as `src/...` lived in the now-archived `legacy/electron`
git tag — kept here for context on what got collapsed.)

- **Platform**: macOS 13.0+ (Ventura)
- **UI**: SwiftUI for content, AppKit for windowing primitives that SwiftUI can't express
  cleanly (NSPanel palette, NSStatusItem, drag receiver on the status button)
- **Concurrency**: Swift Concurrency (`async`/`await`, `Task`, `AsyncStream`)
- **State**: `@Observable` services held by an `AppEnvironment` singleton, injected via
  `.environment(_:)`. No global mutable state outside that container.
- **Persistence**: codable JSON files in `~/.ea/nexus/` (schema-compatible with Electron),
  YAML config via [Yams](https://github.com/jpsim/Yams)
- **No IPC layer**: services and views run in the same process. The `IPC` channel
  constants in `src/shared/ipc.ts` collapse into direct method calls on services.

## Why no SwiftUI `MenuBarExtra`?

`MenuBarExtra` (macOS 13+) is tempting but constrains us:
- Drop-target on the status button (uploader feature) needs the underlying NSStatusItem
  view, which `MenuBarExtra` hides.
- Custom popover sizing/animation (320×400 frameless float) needs `NSPopover` directly.
- Title text changes 1Hz during pomodoro: `MenuBarExtra` re-renders the whole label
  view; `NSStatusItem.button.attributedTitle` is a single property write.

Decision: use AppKit `NSStatusItem` + `NSPopover`, hosted in an `NSApplicationDelegate`.
SwiftUI views are embedded via `NSHostingController`. (See SADR-002.)

## Target Layout

Single Xcode project, **one app target**, no extensions for v1:

```
Nexus.xcodeproj
└── Nexus/
    ├── App/
    │   ├── NexusApp.swift              # @main, AppDelegate adapter
    │   ├── AppDelegate.swift           # NSApp lifecycle, status item, popover, panels
    │   └── AppEnvironment.swift        # DI container — owns all services
    ├── Core/
    │   ├── Paths.swift                 # ~/.ea/nexus/ paths (mirrors PathManager.ts)
    │   ├── Config.swift                # YAML load/save + hot-reload (DispatchSource)
    │   ├── ConfigSchema.swift          # Codable structs matching config.yaml
    │   ├── DataStore.swift             # Generic JSON file store (debounced writes)
    │   ├── Logger.swift                # OSLog + file mirror at ~/.ea/nexus/logs/main.log
    │   ├── Permissions.swift           # AXIsProcessTrusted + grant prompt
    │   ├── Notifications.swift         # UNUserNotificationCenter wrapper
    │   ├── HotKey.swift                # Carbon RegisterEventHotKey wrapper
    │   ├── URLScheme.swift             # NSAppleEventManager handler for nexus://
    │   └── CommandRegistry.swift       # Single command table; palette + URL share it
    ├── Features/
    │   ├── Pomodoro/
    │   │   ├── PomodoroService.swift   # @Observable state machine + timer
    │   │   ├── PomodoroStore.swift     # data.json read/write + archiving
    │   │   ├── PomodoroCommands.swift  # Registers commands with CommandRegistry
    │   │   └── Views/
    │   │       ├── PomodoroPopoverView.swift
    │   │       ├── EditSessionModal.swift
    │   │       ├── StatsView.swift     # Activity calendar + bar + timeline
    │   │       └── ActivityCalendar.swift  # Custom Canvas-drawn heatmap
    │   ├── Tracker/
    │   │   ├── TrackerService.swift    # AX polling, merge algorithm
    │   │   ├── TrackerStore.swift      # tracker/YYYY-MM-DD.json
    │   │   ├── ContextEnricher.swift   # VSCode/browser title parsing
    │   │   └── Views/
    │   │       ├── TrackerView.swift
    │   │       ├── TrackerTimeline.swift
    │   │       ├── AppUsageDonut.swift
    │   │       └── AppRankList.swift
    │   ├── Uploader/
    │   │   ├── UploaderService.swift   # Drop, paste, upload orchestration
    │   │   ├── UploaderStore.swift     # uploader.json + cache mgmt
    │   │   ├── ImageCompressor.swift   # CGImageSource + ImageIO
    │   │   ├── GitHubClient.swift      # URLSession-based REST client
    │   │   └── Views/
    │   │       ├── UploaderPopoverView.swift
    │   │       └── DropZoneView.swift
    │   ├── Palette/
    │   │   ├── PaletteWindow.swift     # NSPanel subclass (non-activating)
    │   │   ├── PaletteView.swift
    │   │   └── PaletteSearch.swift     # Substring + subsequence scoring
    │   ├── Settings/
    │   │   └── SettingsView.swift      # YAML text editor (NSTextView wrapper)
    │   └── MainWindow/
    │       ├── MainWindow.swift        # NSWindow w/ sidebar nav
    │       └── Sidebar.swift
    └── Resources/
        ├── Assets.xcassets             # Tray icons (Template), app icon
        ├── default-config.yaml         # Embedded fallback (same as Electron resources/)
        └── Info.plist                  # LSUIElement, URL scheme, AX usage description
```

## App Lifecycle

```
NSApp launch
  ↓
AppDelegate.applicationDidFinishLaunching
  ↓
AppEnvironment.bootstrap()
    Paths.ensureDirectories()
    Config.load()  → start hot-reload watcher
    Logger.start()
    PomodoroStore.runArchiveSweep()       # 90-day cutoff (ADR-004)
    TrackerStore.loadToday()
    CommandRegistry.shared.registerBuiltins()
    PomodoroCommands.register()
    TrackerCommands.register()
    UploaderCommands.register()
    URLScheme.install()                   # NSAppleEventManager
    HotKey.install(palette: cfg.hotkey)   # Configurable (ADR-010)
    StatusItem.create()                   # NSStatusItem, image, drag types
    Popover.prepare()                     # Lazy: build NSHostingController on first show
    if cfg.tracker.enabled: TrackerService.start()
```

## Service / View Boundary

Services own state and side effects. Views are read-only consumers (apart from action
methods on the service). This mirrors the Electron "main = source of truth, renderer =
projection" principle (architecture.md "Main-Process-as-Source-of-Truth"), but with
direct method calls instead of IPC.

```swift
@Observable @MainActor
final class PomodoroService {
    private(set) var state: PomodoroState = .idle
    private(set) var remaining: TimeInterval = 0
    func start(metadata: SessionMetadata) { ... }
    func pause() { ... }
    func resume() { ... }
    func finishEarly() { ... }
    func exit() { ... }
}

struct PomodoroPopoverView: View {
    @Environment(PomodoroService.self) private var pomodoro
    var body: some View {
        // observe pomodoro.state, pomodoro.remaining
    }
}
```

The `IPC` constants table (`src/shared/ipc.ts`) goes away entirely — there's no channel
to keep type-safe. Service method signatures are the contract.

## Persistence Layer (`Core/DataStore.swift`)

Generic actor that handles debounced JSON writes:

```swift
actor DataStore<T: Codable> {
    let url: URL
    private var pending: T?
    private var flushTask: Task<Void, Never>?

    func write(_ value: T) {
        pending = value
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            await flush()
        }
    }
    func flush() async { /* atomic write to .tmp + rename */ }
}
```

Replaces electron-store's per-`.set()` full-file rewrite with a 200ms debounce. Each
feature owns its own typed `DataStore<T>` — no global key/value bag.

## Logging

Two sinks:
- `OSLog` (subsystem `site.easonsi.nexus`, categories per feature) — visible in Console.app
- File mirror at `~/.ea/nexus/logs/main.log` for parity with the Electron build (5 MB
  rotation, `.1` suffix on rollover)

`Logger.swift` provides `Logger.pomodoro`, `Logger.tracker`, etc.

## Permissions (`Core/Permissions.swift`)

The Electron build cycled through `node-mac-permissions` and a custom permission UI
(PermissionManager.ts). Swift uses the system APIs directly:

| Permission | API | Trigger point |
|---|---|---|
| Accessibility (AX) | `AXIsProcessTrustedWithOptions(prompt: true)` | TrackerService.start() |
| Notifications | `UNUserNotificationCenter.requestAuthorization` | First pomodoro completion |
| Apple Events (browser URL) | `AEDeterminePermissionToAutomateTarget` | First browser title needing URL |

If AX is denied: TrackerService stays disabled, surfaces a banner in Settings → Tracker
with a "Open System Settings" button (`x-apple.systempreferences:`).

## Distribution

`xcodebuild -archive` → `xcodebuild -exportArchive` → `create-dmg` → Sparkle appcast
update.

- Codesign: ad-hoc (`-` identity), same constraint as Electron build (no Apple Developer
  ID). The Electron-side ADR-011 problem (`--deep` breaking nested signatures) doesn't
  apply — single-binary app, no nested frameworks beyond Sparkle's `Autoupdate.app`.
- Quarantine: Homebrew cask `postflight` continues to strip `com.apple.quarantine`.
- Universal binary: `ARCHS = arm64 x86_64`, single DMG drops the per-arch split. Cask
  simplifies (no `arch` block).
- See `migration.md` for the rollout plan.

## What Maps from the Electron Spec

| Electron concept | Swift equivalent |
|---|---|
| `src/shared/types.ts` | `Core/ConfigSchema.swift` + per-feature model files |
| `src/shared/ipc.ts` | **deleted** — direct service method calls |
| `src/preload/index.ts` | **deleted** — no privilege boundary |
| `ConfigManager.ts` + `fs.watch` | `Config.swift` + `DispatchSource.makeFileSystemObjectSource` |
| `DataManager.ts` (electron-store) | `DataStore<T>` actor |
| `PathManager.ts` | `Paths.swift` (static enum) |
| `TrayManager.ts` | `AppDelegate` + `NSStatusItem` |
| `PopupWindow.ts` | `NSPopover` containing `NSHostingController` |
| `MainWindow.ts` | `NSWindowController` + `NSHostingController` |
| `PaletteWindow.ts` (panel-style, ADR-013) | `NSPanel` subclass with `.nonactivatingPanel` style |
| `GlobalHotkey.ts` | `HotKey.swift` (Carbon `RegisterEventHotKey`) |
| `UrlSchemeHandler.ts` | `URLScheme.swift` (`NSAppleEventManager`) |
| `CommandRegistry.ts` | `CommandRegistry.swift` (same shape, Swift struct values) |
| `ErrorBoundary.tsx` (per-feature) | n/a — Swift exceptions don't crash the process; per-view `Result`-typed bindings + a small `FailureView` modifier |
| `electron-log` | `Logger.swift` (OSLog + file mirror) |
| Auto-archiving (ADR-004) | `PomodoroStore.runArchiveSweep()` at launch |
| IPC listener cleanup (ADR-005) | n/a — `@Observable` handles teardown automatically |
| Hash routing (ADR-006) | enum `MainRoute { case stats, tracker, settings }` |
