---
schema_version: 1
id: nexus-007
title: Gate features on `uploader.enabled` and `pomodoro.showPopoverOnComplete`
status: todo
priority: high
estimate: S
labels: [settings, config, gating, feature-gap]
isolation: local
delivery: none
---

## Objective
Read `uploader.enabled` at runtime to hide the uploader route, its palette commands and
the status-item drop target when it is off, and honour `pomodoro.showPopoverOnComplete`
when a focus session completes — so two Settings toggles that are persisted and shown
actually do something.

## Context
- `.ea/spec/uploader.md:169-186` ("## Config (unchanged)") — the config block the
  feature is supposed to obey, starting `uploader: enabled: true`. The spec heading says
  the block is unchanged from Electron, which is why `enabled` reads as authoritative.
- `.ea/spec/uploader.md:162-167` ("## Commands") — the two commands the feature exposes,
  `uploader.openPopover` and `uploader.uploadClipboard`; both are what a disabled
  feature must stop offering.
- `.ea/spec/pomodoro.md:201-205` ("## Config") — "Schema in `ConfigSchema.swift` under
  the `pomodoro.*` block. The `Config.swift` watcher fires `Config.publisher` → service
  rebinds durations live. No app restart for config changes." This is the normative
  statement that a `pomodoro.*` key takes effect without a relaunch.
- `Nexus/Core/ConfigSchema.swift:29-51` — `PomodoroConfig`; `showPopoverOnComplete` is
  declared at line 34 (default `false`) and decoded at line 46.
- `Nexus/Core/ConfigSchema.swift:114-132` — `UploaderConfig`; `enabled` is declared at
  line 115 (default `true`) and decoded at line 125. Both keys are decoded, so both are
  present in `config.config`; neither has a reader.
- `Nexus/Core/Config.swift:9` — `@Published private(set) var config: AppConfig`, and
  `:93-112` — the `DispatchSource` file watcher that reloads on write. Any runtime gate
  can therefore subscribe to `config.$config` and react live, which is what makes this
  an `S` rather than a relaunch-only change.
- `Nexus/Features/Settings/UploaderSettingsForm.swift:17-19` — the "Enable image
  uploader" toggle bound to `$draft.uploader.enabled`. The control works; only its
  effect is missing.
- `Nexus/Features/Settings/PomodoroSettingsForm.swift:48-50` — the "Show popover when
  focus completes" toggle bound to `$draft.pomodoro.showPopoverOnComplete`, next to the
  working `confettiOnComplete` toggle.
- `Nexus/Features/MainWindow/MainRoute.swift:5-9` — `MainRoute` carries `case uploader`
  unconditionally, so the route exists regardless of config.
- `Nexus/Features/MainWindow/MainWindowView.swift:21-23` — the sidebar's `Section("Tools")`
  always renders `sidebarItem(.uploader)`; `:52-60` — the detail switch always maps
  `.uploader` to `UploaderView()`. These are the two places the route becomes visible.
- `Nexus/Features/Uploader/UploaderCommands.swift:6-52` — `register(service:mainWindow:)`
  registers both commands with no `enabled` check; `uploader.open` at `:10-22` and
  `uploader.uploadClipboard` at `:24-51`.
- `Nexus/Features/Uploader/UploaderService.swift:28-37` — `bootstrap()` already
  subscribes to `config.$config.map(\\.uploader)` and re-applies on change; `:145-154` —
  `applyConfig(_:)` reads only `github.token` / `.owner` / `.repo` to compute
  `isConfigured`. This is the natural place to also record `enabled`, and the
  subscription that makes the gate live.
- `Nexus/Features/Tracker/TrackerService.swift:55-70` — `applyConfig(_:)` is the only
  runtime `.enabled` gate in the app: `if !cfg.enabled { stopPolling(); status = .stopped; ... }`.
  `grep -rn "\\.enabled" Nexus/` finds it at line 56 and nowhere else in a runtime path.
  This is the pattern to mirror, not a new mechanism.
- `Nexus/Features/Pomodoro/PomodoroService.swift:151-175` — `finalizeOnZero(kind:startedAt:total:)`,
  the completion path. It persists, notifies, fires confetti when
  `config.config.pomodoro.confettiOnComplete` (line 159) and then transitions; it never
  consults `showPopoverOnComplete`. Note that the neighbouring `confettiOnComplete` gate
  at line 159 is the precedent for reading a `pomodoro.*` flag here.
- `Nexus/App/AppDelegate.swift:140-156` — `togglePopover()`, `private` to `AppDelegate`,
  is the only code that shows the pomodoro `NSPopover`. `PomodoroService` cannot reach
  it today, so honouring `showPopoverOnComplete` needs either a callback into the
  AppDelegate or the decision moved to whoever owns the popover. Lines 146-153 document
  that the popover deliberately does **not** call `NSApp.activate(ignoringOtherApps:)`.
- `Nexus/App/AppDelegate.swift:78-84` — `handleStatusItemDrop(payloads:)` is the
  status-item drop target: it stashes the images and calls
  `environment.mainWindow.show(route: .uploader)`. This is the third uploader entry point
  a disabled feature must not leave live.
- `Nexus/Features/Uploader/StatusItemDropView.swift:29-36` — the transparent overlay
  that registers `.fileURL`, `.png`, `.tiff` and forwards drops. It is installed on the
  status button, so gating the *handler* (or not installing the view) both work; the
  issue leaves that choice open.
- `Nexus/Features/MainWindow/MainWindowController.swift:35-37` — `show()` calls
  `NSApp.setActivationPolicy(.regular)` and `NSApp.activate(ignoringOtherApps: true)`.
  Any gate must not route through here as a side effect of showing a completion popover.
- `project.yml:35-37` — one target and no test target, so verification is inspection
  plus a manual config flip, not a unit test.

## Tasks
- [ ] Add a runtime reader for `config.uploader.enabled` and drive every uploader entry point from it: the sidebar item and `.uploader` detail case (`MainWindowView.swift:21-23`, `:52-60`), the two palette commands (`UploaderCommands.swift:6-52`), and the status-item drop handler (`AppDelegate.swift:78-84`)
- [ ] Add a runtime reader for `config.pomodoro.showPopoverOnComplete` in the completion path (`PomodoroService.finalizeOnZero`, `PomodoroService.swift:151-175`) so the toggle changes behaviour
- [ ] Make the popover-show path reachable from wherever the flag is read — `togglePopover()` is `private` to `AppDelegate` (`AppDelegate.swift:140-156`), so expose a callback or move the decision to the popover's owner
- [ ] Make both gates react to live config changes by subscribing to `config.$config` the way `UploaderService.bootstrap()` (`UploaderService.swift:30-35`) and `TrackerService.bootstrap()` already do, rather than reading once at launch
- [ ] Follow `TrackerService.applyConfig` (`TrackerService.swift:55-70`) as the single gating idiom — do not introduce a second mechanism (a separate `FeatureFlags` type, a cached boolean written at launch, or per-view `if` checks scattered across files)
- [ ] Keep the tracker's existing gate and the uploader's `isConfigured` logic unchanged; this issue adds readers, it does not rework either feature
- [ ] Update `.ea/spec/uploader.md` and/or `.ea/spec/pomodoro.md` if the landed behaviour differs from what they state about the two keys

## Acceptance
- [ ] `grep -rn "uploader.enabled\\|config.uploader.enabled\\|\\.uploader\\.enabled" Nexus/` returns a reader outside `ConfigSchema.swift` and `UploaderSettingsForm.swift`
- [ ] `grep -rn "showPopoverOnComplete" Nexus/` returns a reader outside `ConfigSchema.swift`, `PomodoroSettingsForm.swift`, and `Nexus/Resources/default-config.json`
- [ ] With `uploader.enabled = false` in `config.json`, the sidebar has no "Image Uploader" entry, the palette offers neither `uploader.open` nor `uploader.uploadClipboard`, and dropping an image on the status item does not open the main window's uploader route
- [ ] Flipping `uploader.enabled` back to `true` restores all of those without a relaunch, through the existing config watcher (`Config.swift:93-112`)
- [ ] With `pomodoro.showPopoverOnComplete = true`, a focus session that reaches zero shows the pomodoro popover; with `false`, it does not — and neither case activates Nexus's main window
- [ ] The completion path still persists the session, posts the notification, and fires confetti when `confettiOnComplete` is on (`PomodoroService.swift:153-171`)
- [ ] `tracker.enabled = false` still stops polling through the existing gate — no regression to `TrackerService.swift:56`
- [ ] `forge check nexus-007` passes

## Boundaries
- Always: read both flags from `ConfigService.config` at the moment of use, so the hot-reload contract in `.ea/spec/pomodoro.md:203-205` still holds
- Always: treat `TrackerService.applyConfig` as the reference implementation of an `enabled` gate, so the app has one idiom rather than two
- Never: gate by hiding UI while leaving the command runnable — `.ea/spec/uploader.md:169-186` says `enabled` gates the feature, so every entry point goes quiet together
- Never: force the main window forward as a side effect of the completion popover; `MainWindowController.show()` sets `.regular` and calls `NSApp.activate` (`MainWindowController.swift:35-37`), and the popover is deliberately non-activating (`AppDelegate.swift:146-153`)
- Never: read either flag once in `init` and cache it; that breaks the no-relaunch behaviour the spec promises
- Ask: whether the status-item drop target should be uninstalled while the uploader is disabled, or kept installed but inert — both satisfy the acceptance, and the first also removes the drop highlight (`StatusItemDropView.swift:100-110`)
- Ask: whether `showPopoverOnComplete` applies to break completions too, or only to focus completions — the toggle label says "when focus completes" (`PomodoroSettingsForm.swift:48`) and the spec does not say
- Ask: whether `MainRoute.uploader` should be removed from the enum entirely while disabled or just hidden from the sidebar — removing the case is a larger, compile-visible change that overlaps nexus-008
