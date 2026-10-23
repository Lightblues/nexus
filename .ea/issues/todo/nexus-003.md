---
schema_version: 1
id: nexus-003
title: Launch the built app in CI before publishing a release
status: todo
priority: urgent
estimate: S
labels: [ci, release, verification]
isolation: local
delivery: none
---

## Objective
Add a step to the release workflow that launches the exported `Nexus.app` binary on
the runner, asserts the process is still alive after a few seconds and that `main.log`
carries the launch banner, then kills it — so a cold-cache launch crash fails the build
instead of shipping to a user.

## Context
- `.github/workflows/build.yml:39-54` — the entire post-build surface of the `build`
  job: `Build DMG` (`:39-42`), `Upload DMG artifact` (`:44-50`, whose only assertion is
  `if-no-files-found: error` on `dist/Nexus-*.dmg`), `Show dist contents` (`:52-53`).
  No step ever executes the app. This is where the new step goes.
- `scripts/build-mac.sh:88-96` — `xcodebuild -exportArchive` writes the runnable bundle
  to `$BUILD_DIR/export/Nexus.app` (`BUILD_DIR="$PROJECT_DIR/build"`, `:22`), so the
  executable the CI step must launch is `build/export/Nexus.app/Contents/MacOS/Nexus`.
  This is the same bundle the DMG is staged from (`:114`), so the check covers the
  artefact that ships.
- `Nexus/Core/Logger.swift:21-30` — `Log.writeLaunchBanner()` writes
  `===== Launched Nexus v<version> (pid=<pid>) =====` to the file sink. This is the
  string the check greps for.
- `Nexus/App/AppDelegate.swift:17-18` — `applicationDidFinishLaunching` calls
  `Log.writeLaunchBanner()` as its first statement, so the banner proves the process
  reached the AppKit launch callback rather than dying during service construction.
- `Nexus/App/AppEnvironment.swift:22-46` — `AppEnvironment.init` (a stored property of
  `AppDelegate`, `:11`) runs `try Paths.ensureDirectories()` and `try Database(url:)`
  inside a `do/catch` whose only branch is `fatalError` (`:26-31`). A failure here is
  the other launch-time crash class the check must catch.
- `Nexus/Features/MainWindow/MainWindowController.swift:55-56` — `makeWindow()` still
  carries `guard let env = environment else { fatalError("MainWindowController:
  environment not attached") }`. The §3.6 fix added a deferral guard on `show()`
  (`:18-28`), so this `fatalError` is now reachable only through a path that bypasses
  `show()` — it stays as the signature the check is written to catch.
- `.ea/spec/pitfalls.md:374-446` (§3.6) — the concrete regression: v1.2.1 launched fine
  on the developer machine and crashed on a cold-cache `brew upgrade` install. The
  quoted crash signature is `Nexus/MainWindowController.swift:46: Fatal error:
  MainWindowController: environment not attached`; that line number is from the
  pre-fix source, and the same `fatalError` sits at `MainWindowController.swift:56`
  today (the guard the fix added shifted it down ten lines). The section's closing
  lesson (`:442-446`) is that a warm dev build masks launch-time races and a cold-cache
  install is the only reproducer — a CI runner is a cold cache by construction.
- `project.yml:54` — `CFBundleShortVersionString: "1.2.3"` is what the banner prints,
  so the grep can assert the resolved version instead of a wildcard.
- `CLAUDE.md:10` — records `./scripts/build-mac.sh` → `dist/Nexus-<version>.dmg` as the
  build path, so this check reuses the existing script rather than adding a second one.
- `.ea/report/gap-analysis.md` §2 V-01 — the finding this issue executes; its "Smallest
  automated check" paragraph is the shape of the step.

## Tasks
- [ ] Add a step to the `build` job in `.github/workflows/build.yml` that runs after `Build DMG` (`:39-42`) and launches `build/export/Nexus.app/Contents/MacOS/Nexus` in the background with stdout/stderr redirected to a file, so a crash message is captured rather than lost
- [ ] Sleep long enough for `applicationDidFinishLaunching` and the banner write, then assert the process is still alive (`kill -0 <pid>`); when it is not, print the captured output and the tail of `main.log` and exit non-zero
- [ ] Assert `~/Library/Logs/site.easonsi.nexus/main.log` exists and contains `===== Launched Nexus v`; a missing file or a missing banner fails the step even when the process is still alive
- [ ] Kill the launched process at the end of the step (and on the failure path) so no `Nexus` process survives into later steps
- [ ] Make the failure message name the crash class — echo the captured stderr, which is where a `fatalError` line lands, and the last lines of `main.log`
- [ ] If the runner has no aqua/WindowServer session (see `Ask:`), make the step report that condition explicitly instead of reporting a launch crash

## Acceptance
- [ ] `.github/workflows/build.yml` contains a step that executes `build/export/Nexus.app/Contents/MacOS/Nexus` after the DMG is built
- [ ] With a launch-path `fatalError` reintroduced, the job fails and the failure output contains the `fatalError` text
- [ ] On the current tree the job passes: the process is alive after the sleep and `main.log` contains `===== Launched Nexus v1.2.3` (the version from `project.yml:54`)
- [ ] The step needs no `xcuserdata` or other local Xcode state — it passes on a clean `macos-14` checkout
- [ ] No `Nexus` process survives the step (`pgrep -f "Nexus.app/Contents/MacOS/Nexus"` returns nothing afterwards)
- [ ] The existing `Upload DMG artifact` and `Show dist contents` steps still run unchanged, and the `release` job is untouched

## Boundaries
- Always: launch the exported bundle from `build/export/`, the same one the DMG is staged from (`scripts/build-mac.sh:109-115`), so the check covers what ships
- Always: assert the launch banner in `main.log` in addition to process liveness — a process that starts and then hangs before `didFinishLaunching` would pass a liveness-only check
- Never: launch from a mounted DMG here; mounting and inspecting the DMG is nexus-012's job, and duplicating it would double the failure surface
- Never: soften the step with `continue-on-error` or `|| true`; the whole point is that a cold-cache launch crash fails the build
- Never: leave the launched process running — a menu-bar app holding `site.easonsi.nexus` can interfere with later steps on the runner
- Ask: whether the `macos-14` runner has an aqua session. If it does not, `Nexus.app` cannot reach WindowServer and the step must distinguish that from the crash it guards; the implementer should decide between setting up a session, asserting only that the process did not exit with a `fatalError`, or moving the check to a self-hosted runner
- Ask: before widening this into a UI smoke test (driving the status item, opening the popover). Launch-plus-banner is the smallest check that catches V-01; anything more is a different, larger issue
