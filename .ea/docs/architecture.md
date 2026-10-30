# Architecture

## Overview

Three parts: the Mac app records and acts on one Mac, the server holds every Mac's data
and serves it, and the CLI and web app read it.

```
Nexus.app (each Mac)                 services/server (devcloud)               readers
  pomodoro, tracker, settings  ──sync──▶ records per user ──▶ day summaries ──▶ cli/ (nexus), web app (/app)
  in nexus.db (SQLite)        ◀──────── (last write wins)                 └──▶ /export → sonar → intake raw
```

The app is one process: status item, popover, main window, palette panel, and the
background services.

- **Platform**: macOS 13.0+. SwiftUI for content, AppKit where SwiftUI cannot express it
  (NSPanel palette, NSStatusItem with a drop target, NSPopover). No `MenuBarExtra`: it
  hides the status button (needed for drops) and re-renders the label on every 1 Hz
  pomodoro tick (SADR-002).
- **State**: `ObservableObject` services owned by `AppEnvironment`; views read them and
  call their methods. No IPC.
- **Persistence**: one GRDB SQLite database, `nexus.db`, for pomodoro, tracker, uploader
  history, and settings.

## Target Layout

`project.yml` (XcodeGen) declares the app target `Nexus`, the hosted test bundle
`NexusTests`, and the local package `Packages/NexusSync` (sync logic, tested on Linux).

```
Nexus/
├── App/            NexusApp (@main NexusMain; bare under XCTest), AppDelegate (status item, popover), AppEnvironment (services)
├── Core/           Paths, Logger, Config (settings in nexus.db), ConfigSchema (AppConfig), Permissions,
│                   Notifications, HotKey (Carbon), URLScheme (nexus://), CommandRegistry, Database/ (GRDB, migrations)
├── Features/
│   ├── Pomodoro/   PomodoroService (state machine), PomodoroRepository, commands, popover and edit views
│   ├── Stats/      pomodoro stats and activity calendar
│   ├── Tracker/    TrackerService (poll, merge), ActiveAppProbe (AX), ContextEnricher, IdleDetector, TrackerRepository, views
│   ├── Uploader/   UploaderService, ImageCompressor (ImageIO), GitHubUploader, status-item drop view, views
│   ├── Palette/    PaletteController, PalettePanel (NSPanel), PaletteSearch, PaletteView
│   ├── Settings/   one form per tab, Sync tab
│   ├── Sync/       SyncConnection (sync.json), SyncCoordinator (owns NexusSync's SyncEngine)
│   └── MainWindow/ window controller, routes, sidebar
└── Resources/      Assets.xcassets, Info.plist
```

## App Lifecycle

```
NexusMain.main()                    under XCTest: bare NSApplication, nothing below
AppDelegate.applicationDidFinishLaunching
  Log.writeLaunchBanner()
  AppEnvironment.init                open nexus.db (migrations), build services
  status item + popover
  AppEnvironment.bootstrap()
    attach main window and palette   synchronous, before any await
    config.bootstrap()               settings from nexus.db (imports a legacy config.json once)
    pomodoro, tracker, uploader bootstrap
    register commands, install nexus:// handler and the palette hotkey
    sync.start()
```

## Data Layout

Keyed by the bundle id `site.easonsi.nexus` (frozen: Accessibility grants and backups
follow it), resolved through `FileManager` (SADR-015):

| Kind | Location | Contents |
|---|---|---|
| User data | `~/Library/Application Support/site.easonsi.nexus/` | `nexus.db` (+ `-wal`, `-shm`): records and the `settings` table; `sync.json` (this Mac's sync connection, mode 0600) |
| Regenerable | `~/Library/Caches/site.easonsi.nexus/` | `uploader-thumbnails/` |
| Logs | `~/Library/Logs/site.easonsi.nexus/` | `main.log` + 4 rotated generations; `beta-update.log` on beta Macs |
| UI state | `~/Library/Preferences/site.easonsi.nexus.plist` | window frame autosave |

Settings are rows (`settings`: dotted key → JSON), the same keys sync uses; there is no
config file to hand-edit. Change them in Settings or with `nexus config set` (through the
server). A `config.json` from v1.3.1 or earlier is imported on first launch and renamed
`config.json.imported`.

## Logging

OSLog (subsystem `site.easonsi.nexus`, categories `pomodoro`, `tracker`, `uploader`,
`palette`, `app`, `config`, `sync`) and a file mirror at `main.log` (5 MB × 4). Each
launch writes `===== Launched Nexus vX.Y.Z (build N, pid=P) =====`.

## Permissions (`Core/Permissions.swift`)

| Permission | Asked when |
|---|---|
| Accessibility | The tracker starts enabled but untrusted: the system prompt once per launch, a notification after 10 min (`tracker.md`) |
| Notifications | First notification |
| Apple Events, per browser | First URL read from that browser |

## Distribution

- `scripts/build-mac.sh`: `xcodebuild archive` (Release, `arm64 x86_64`), export, sign,
  DMG. Fails on a broken signature or a missing architecture.
- Signing: CI signs with a stable self-signed identity (SADR-018), so macOS keeps the
  Accessibility grant across upgrades; local builds are ad-hoc. No Developer ID, no
  notarization; the cask strips quarantine.
- CI (`.github/workflows/build.yml`), on every push to `main` and pull request: unit tests
  (`ci-checks.sh unit`), build, launch check, DMG check. A push to `main` replaces the
  `nexus-beta` pre-release and the `nexus@beta` cask; a `nexus-v*` tag publishes a release
  and the `nexus` cask. On a Mac, `scripts/beta.sh install` follows the beta.
- Tests: `NexusTests` (XCTest) is hosted in Nexus.app, which starts no services under
  XCTest, so the suite never touches the user's data. It covers pure logic and the
  settings store on an in-memory database.
