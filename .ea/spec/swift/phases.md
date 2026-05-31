# Implementation Phases

Time estimates assume **~one developer, focused**. Each phase ends with a buildable,
runnable artifact — no big-bang merges.

## Phase 0 — Project scaffold (~1 day)

**Output**: empty Xcode project that launches and shows a status item.

- Xcode project, single `Nexus` target, deployment target macOS 13.0.
- `Info.plist`: `LSUIElement = YES`, URL scheme `nexus`, AX usage description.
- `AppDelegate` creates `NSStatusItem` with placeholder icon.
- SwiftPM packages added: Yams, Sparkle.
- `.gitignore`, `xcodebuild -archive` smoke test.

**Exit criteria**: status item visible, click does nothing useful, `xcodebuild`
produces a `.app` bundle that launches without crash.

---

## Phase 1 — Core infra + Pomodoro MVP (~1 week)

**Output**: working Pomodoro timer with persistence and notifications. Feature
parity with the most-used Electron path.

- `Core/Paths.swift`, `Core/Logger.swift` (OSLog + file mirror).
- `Core/Config.swift` + `ConfigSchema.swift` (Yams-backed; hot-reload via
  `DispatchSourceFileSystemObject`).
- `Core/DataStore.swift` (debounced writer actor).
- `Core/Notifications.swift`.
- `Core/Permissions.swift` (AX, Notifications).
- `Pomodoro/PomodoroService.swift` (state machine, tick, autoBreak).
- `Pomodoro/PomodoroStore.swift` (data.json + archive sweep).
- `Pomodoro/Views/PomodoroPopoverView.swift` (ring, summary, start button).
- `Pomodoro/Views/EditSessionModal.swift`.
- `NSPopover` wired to status item button.
- Status item title shows `MM:SS` countdown during running state.

**Exit criteria**:
- Click status icon → popover appears.
- Start a Focus session → ring animates, title updates, notification fires at end.
- Quit + relaunch → daily count and last session metadata persist.
- Re-grant Accessibility from Electron build → no re-prompt.

---

## Phase 2 — Tracker (~1 week)

**Output**: window-tracking feature on par with Electron, but using AX.

- `Tracker/ActiveAppProbe.swift` (AX-based).
- `Tracker/IdleDetector.swift` (IOKit HID).
- `Tracker/ContextEnricher.swift` (VSCode title parser, browser URL via compiled
  `NSAppleScript`).
- `Tracker/TrackerService.swift` (poll loop, merge algorithm, in-memory buffer).
- `Tracker/TrackerStore.swift` (per-day JSON files, atomic flush).
- `Tracker/Views/TrackerView.swift`, `TrackerTimeline.swift`, `AppUsageDonut.swift`,
  `AppRankList.swift`.
- MainWindow shell with sidebar (Statistics / Tracker / Settings); only Tracker tab
  populated this phase.

**Exit criteria**:
- Tracker runs in background, accumulates records, flushes on schedule.
- Read existing Electron-produced `tracker/YYYY-MM-DD.json` files and render
  identical timeline.
- AX denial → graceful disable + Settings banner.

---

## Phase 3 — Stats + Settings + Uploader (~1.5 weeks)

**Output**: feature parity with Electron 0.7.

- `Pomodoro/Views/StatsView.swift` (Activity Calendar, weekly bar, daily timeline,
  session list).
- `Pomodoro/Views/ActivityCalendar.swift` (Canvas-drawn heatmap reading active +
  archived sessions via `SessionHistoryService`).
- Swift Charts replacement for Recharts in StatsView.
- `Settings/SettingsView.swift` — YAML editor (NSTextView with simple YAML syntax
  highlighting).
- `Uploader/ImageCompressor.swift` (ImageIO-based, JPEG + WebP + PNG paths).
- `Uploader/GitHubClient.swift` (URLSession + base64 PUT).
- `Uploader/UploaderService.swift`, `UploaderStore.swift`.
- `Uploader/Views/UploaderPopoverView.swift`, `DropZoneView.swift`.
- `StatusButtonDropView.swift` for tray icon drop receiver.
- Recent uploads list with thumbnail cache.

**Exit criteria**:
- Drag image into popover → compressed → uploaded → CDN URL on clipboard.
- Drag image onto status icon → popover opens with image preloaded.
- Stats tab matches the Electron version pixel-roughly (calendar, charts, list).
- Settings tab edits config.yaml, hot-reload picks up changes.

---

## Phase 4 — Palette + URL scheme + Hotkey (~3 days)

**Output**: command palette with global hotkey and `nexus://` URL scheme.

- `Core/CommandRegistry.swift`.
- `Core/HotKey.swift` (Carbon).
- `Core/URLScheme.swift` (NSAppleEventManager).
- `Palette/PaletteWindow.swift` (NSPanel).
- `Palette/PaletteView.swift` + `PaletteSearch.swift`.
- Per-feature command registration files (`PomodoroCommands.swift`, etc.).
- Footer in palette → openMain action.

**Exit criteria**:
- Cmd+Shift+Space opens palette without activating Nexus app.
- `open nexus://command/pomodoro.start` from terminal triggers focus session.
- Pomodoro running while palette is open → palette subtitle reads live remaining
  time.
- Dismiss palette → previously active app keeps focus, MainWindow (if open) keeps
  Z-order.

---

## Phase 5 — Distribution (~3 days)

**Output**: shipped via Homebrew tap, auto-update enabled.

- `xcodebuild` archive script (`scripts/build-mac.sh`).
- `create-dmg` integration → `Nexus-X.Y.Z.dmg`.
- Sparkle 2 framework: `appcast.xml` generator + EdDSA signing key.
- GitHub Action `build.yml` (port of Electron `build.yml`):
  - Trigger: tag `nexus-vX.Y.Z`.
  - Steps: build → sign → notarize-skip (ad-hoc) → DMG → release → cask bump.
- Cask `Casks/nexus.rb` simplification (no per-arch block).
- README + spec sync.

**Exit criteria**:
- `git tag nexus-v1.0.0 && git push --tags` produces a GitHub Release with DMG +
  appcast entry.
- `brew upgrade --cask lightblues/tap/nexus` from existing Electron install → Swift
  build replaces it; AX permission survives; data files load.
- Installed user gets a Sparkle prompt on next minor release.

---

## Phase 6 — Polish + cleanup (~3 days)

- Performance pass: Instruments time profile; verify popover open < 60 ms, idle CPU
  < 0.5%.
- Memory pass: verify steady-state RSS < 50 MB with all features active.
- Bug bash on beta tap channel.
- Remove the `.electron-bak` migration backup after a successful release window
  (≥1.1).
- Archive Electron source on `legacy/electron` branch + tag.

---

## Total: ~4–5 weeks

| Phase | Effort |
|---|---|
| 0 Scaffold | 1 day |
| 1 Core + Pomodoro | 1 week |
| 2 Tracker | 1 week |
| 3 Stats + Settings + Uploader | 1.5 weeks |
| 4 Palette + URL + Hotkey | 3 days |
| 5 Distribution | 3 days |
| 6 Polish | 3 days |

Slack: ~1 week for surprises (Sparkle EdDSA setup, AX edge cases, Charts custom
styling, codesign quirks).

## Risk register

| Risk | Mitigation |
|---|---|
| ImageIO PNG output noticeably larger than sharp | Keep optional `libimagequant` link as v2 work; document compression ratio in beta |
| Apple tightens ad-hoc codesign rules | Watch macOS releases; budget for paid Apple Developer ID ($99/yr) as fallback |
| Carbon HotKey API deprecation | Pinned dep; `Magnet`/`Rectangle` actively use it; if removed, switch to MASShortcut |
| AX semantics change between macOS versions | Beta-test on macOS 13 / 14 / 15 before each release |
| Yams transitive break (Swift 6 strict concurrency) | Pin to known-good version; add a smoke test in CI |
| Bundle ID continuity edge case (re-prompt) | Beta phase with explicit "did your AX grant survive?" survey |

## Out of scope for v1

- App Intents / Shortcuts.app integration (post-v1, easy add)
- Dock icon visibility toggle (currently `LSUIElement=YES`, no Dock icon — same as Electron)
- Plugin/extension API
- Cloud sync of pomodoro/tracker data
- iOS companion app
