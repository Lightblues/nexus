---
schema_version: 1
id: nexus-014
title: Guard `PaletteController` against the cold-cache ordering
status: todo
priority: high
estimate: S
labels: [core, palette, launch-race, debt]
isolation: local
delivery: none
---

## Objective
Give `PaletteController.show()` the same deferred-attach guard `MainWindowController.show()`
already has, so the `makePanel()` `fatalError` is unreachable when the global hotkey fires
before `AppEnvironment.bootstrap()` has attached the palette — closing the half of §3.6's
fix that v1.2.2 left open.

## Context
- `Nexus/Features/Palette/PaletteController.swift:30-39` — `show()`, the method to change.
  `:31` calls `makePanel()` unconditionally when `panel == nil` and there is no
  `environment == nil` check anywhere in the method; `:32-38` then position the panel,
  order it front, make it key, install the click-outside monitors, and post
  `.paletteDidShow`.
- `Nexus/Features/Palette/PaletteController.swift:82-83` — `makePanel()`'s
  `guard let env = environment else { fatalError("PaletteController: environment not
  attached") }`. This is the crash site. The fix must make it unreachable through `show()`,
  not delete it.
- `Nexus/Features/Palette/PaletteController.swift:10` — `private weak var environment:
  AppEnvironment?`, the optional the guard reads; `:18-20` is `attach(environment:)`, its
  only writer.
- `Nexus/Features/Palette/PaletteController.swift:22-28` — `toggle()`, which calls `show()`
  in its `else` branch. It needs no guard of its own: the deferral belongs in `show()` so
  every caller inherits it.
- `Nexus/Features/MainWindow/MainWindowController.swift:18-29` — the guard to mirror.
  `:19-24` is the comment explaining the race; `:25-28` is the guard that defers one
  runloop tick via `DispatchQueue.main.async { [weak self] in self?.show() }`. This is the
  reference implementation and the exact shape the palette guard must match.
- `Nexus/Features/MainWindow/MainWindowController.swift:55-56` — the same `fatalError`
  shape in `makeWindow()`, whose assertion the deferral protects. Both controllers keep the
  assertion; the symmetry is the point.
- `Nexus/App/AppEnvironment.swift:49-57` — `bootstrap()`'s synchronous prefix. `:50-55` is
  the comment that states the ordering contract, and `:56-57` are the
  `mainWindow.attach` / `palette.attach` calls that satisfy it. Nothing but the comment
  enforces the order, which is what T-03 records as the cost.
- `Nexus/App/AppEnvironment.swift:97-99` — `installHotkey()`, whose closure calls
  `palette.toggle()` (`:99`). This is the **only** caller of `show()` / `toggle()` in the
  app: the command registry registers 15 ids (`grep -n 'id: "' Nexus/`) and none is
  `palette.*`, and no `Scene` mounts a palette view. That is why the crash is *latent*
  rather than live today.
- `Nexus/App/AppEnvironment.swift:85` — the `installHotkey()` call site, 28 lines below the
  `:56-57` attach calls, and `:86-92` re-installs the hotkey on every
  `config.hotkey.palette` change. Both paths run after the attach calls, so on the current
  order the environment is always attached by the time the hotkey can fire.
- `Nexus/App/NexusApp.swift:36-40` — `SettingsTrampoline.route()`, whose `:38` calls
  `appDelegate.environment.mainWindow.show(route: .settings)` from `.onAppear` and
  `.onChange(of: hostWindow)`. This is the live pre-bootstrap caller §3.6 fixed for
  MainWindow, and the template for the future `Scene`-mounted caller that would expose the
  palette.
- `.ea/spec/pitfalls.md:374-446` (§3.6) — the recorded regression: v1.2.1 launched fine on
  the developer machine and crashed on a cold-cache `brew upgrade` install with the stderr
  signature `Nexus/MainWindowController.swift:46: Fatal error: MainWindowController:
  environment not attached`. Its "Fix — two layers" block prescribes exactly the two halves
  this issue closes.
- `.ea/spec/pitfalls.md:435-440` — the "General rule": anything dispatched from an
  `App.body` Scene can run before the bootstrap `Task`'s first `await` hop, and "Anything
  that requires `await` ordering needs its own race guard at the call site." The palette
  guard is that rule applied to the second controller.
- `.ea/report/gap-analysis.md` §4 T-03 — the finding this issue executes. It records the
  palette half as "latent rather than live" and names the cost as "a crash class that stays
  invisible until the next cold-cache release".
- `.ea/report/gap-analysis.md` §4.2 — two supporting observations in the same path: the
  duplicated `.environmentObject(routeRequest)` at `MainWindowController.swift:65-66`, and
  the 40-line distance between `AppEnvironment.swift:56-57` and `:98`.
- `Nexus/Features/Palette/PalettePanel.swift:9-31` — the `NSPanel` subclass `makePanel()`
  builds (`canBecomeKey = true`, `canBecomeMain = false`). Context for what the deferred
  call eventually constructs, and why the deferral must be a bare re-entry rather than a
  partial show.
- `Nexus/Core/Logger.swift:17` — `Log.palette`, the category available if the deferral is
  logged (see `Ask:`).
- `project.yml:35-37` — the single `Nexus` target; there is no test target, so this issue's
  verification is static and manual until nexus-013 lands.

## Tasks
- [ ] Add an `environment == nil` guard as the first statement of `PaletteController.show()` (`:30`) that defers one runloop tick and returns, mirroring `MainWindowController.show()` (`:25-28`) in shape
- [ ] Keep the deferral a bare re-entry — `DispatchQueue.main.async { [weak self] in self?.show() }` — so no part of the show sequence (position, `orderFrontRegardless`, `makeKey`, the click-outside monitors, `.paletteDidShow`) runs against a nil environment
- [ ] Leave `makePanel()`'s `fatalError` (`:83`) in place; the guard makes it unreachable through `show()`, it does not make the assertion wrong
- [ ] Leave `toggle()` (`:22-28`) unchanged — it reaches `show()` in its `else` branch and inherits the guard, and a second guard there would be a second place to keep in sync
- [ ] Keep `AppEnvironment.bootstrap()`'s synchronous prefix (`:56-57`) and its comment (`:50-55`) exactly as they are; the guard is belt-and-suspenders on top of the ordering, not a replacement for it
- [ ] Confirm the hotkey re-install sink (`AppEnvironment.swift:86-92`) still runs after the attach calls — `config.bootstrap()` (`:59`) and the subscription are both below `:57` today, so record the confirmation rather than moving anything
- [ ] If the deferral is logged (see `Ask:`), use `Log.palette` (`Logger.swift:17`) and name the method, so a future cold-cache report shows the guard fired

## Acceptance
- [ ] `PaletteController.show()` returns before calling `makePanel()` when `environment` is nil, and schedules exactly one re-entry on the next runloop tick
- [ ] Constructing a `PaletteController` and calling `show()` without `attach(environment:)` neither crashes nor creates a panel; the `fatalError` at `:83` is unreachable through `show()`
- [ ] Both assertions survive: `grep -c 'environment not attached' Nexus/Features/Palette/PaletteController.swift Nexus/Features/MainWindow/MainWindowController.swift` returns one hit per file
- [ ] `grep -n "DispatchQueue.main.async" Nexus/Features/Palette/PaletteController.swift` returns the single deferral line, matching the shape of `MainWindowController.swift:26`
- [ ] The guard lives in one place: `grep -c "environment != nil" Nexus/Features/Palette/PaletteController.swift` returns 1
- [ ] With the environment attached the visible behaviour is unchanged — `show()` still creates the panel on first call, positions it on the active screen, calls `orderFrontRegardless()` and `makeKey()`, installs the click-outside monitors, and posts `.paletteDidShow` exactly once
- [ ] `if panel == nil { panel = makePanel() }` (`:31`) still bounds the panel count: repeated deferrals before `attach` do not build more than one
- [ ] `AppEnvironment.swift:56-57`, `:85` and `:97-99` are unchanged, so the hotkey reaches `palette.toggle()` on the same ordering as before
- [ ] `git show --stat f6010ae` (the v1.2.2 fix) touched `MainWindowController.swift` and `AppEnvironment.swift` but not `PaletteController.swift`; after this change the two `show()` guards are structurally the same

## Boundaries
- Always: copy `MainWindowController.show()`'s guard (`:25-28`) rather than inventing a second deferral mechanism, so the two controllers read the same and a future fix lands in both
- Always: keep `makePanel()`'s `fatalError` as the invariant's last line of defence; making it unreachable through `show()` is the property to preserve, not deleting it
- Always: defer by re-entering `show()` on the next runloop tick, which is the mechanism §3.6 prescribes (`pitfalls.md:435-440`)
- Never: make `environment` non-optional, or construct a throwaway `AppEnvironment` to satisfy the guard — `AppEnvironment.init` opens the database (`AppEnvironment.swift:26-31`) and a second instance would open a second `DatabaseQueue` on the same file
- Never: move `palette.attach` out of `bootstrap()`'s synchronous prefix (`:57`); that call is the other half of §3.6's fix, and nexus-003 asserts the same launch path in CI
- Never: remove or weaken `MainWindowController`'s guard while adding the palette one, or "unify" the two by dropping the deferral — the guard is the fix, not redundancy
- Never: widen this into a palette feature change; the scope is one guard in one method
- Ask: whether to log the deferral. `MainWindowController`'s guard is silent; logging it through `Log.palette` (`Logger.swift:17`) would make a future cold-cache report show the guard fired, at the cost of a second behavioural difference between the two controllers
- Ask: whether the duplicated `.environmentObject(routeRequest)` at `MainWindowController.swift:65-66` (§4.2) should ride along. It has no runtime effect and is not part of T-03's crash class, but it sits in the same window-building path
- Ask: whether to cover the guard with a test once nexus-013's `NexusTests` target exists. `PaletteController` is `@MainActor` and `makePanel()` builds AppKit views, so the test would have to assert the deferral without instantiating the panel — decide when that target lands rather than blocking this S-sized fix on it
