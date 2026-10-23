---
schema_version: 1
id: nexus-002
title: Issue the Accessibility prompt when the tracker starts
status: todo
priority: urgent
estimate: S
labels: [tracker, permissions, feature-gap]
isolation: local
delivery: none
---

## Objective
Call `Permissions.promptAccessibility()` the first time the tracker turns polling on,
so macOS raises its own Accessibility prompt and the user can grant access from that
dialog instead of having to find Privacy & Security → Accessibility and add Nexus by
hand.

## Context
- `.ea/spec/architecture.md:253-257` — the Permissions table names
  `AXIsProcessTrustedWithOptions(prompt: true)` as the Accessibility API and
  `TrackerService.start()` as its trigger point. This is the normative statement the
  app does not implement.
- `.ea/spec/tracker.md:156-162` ("## Permissions") — "AX: requested via
  `Permissions.requestAccessibility()` on first `TrackerService.start()`." The
  sentence states the intent; the symbol it names does not exist (see the next two
  entries). `TrackerService` has no `start()` either — the launch path is
  `bootstrap()`.
- `Nexus/Core/Permissions.swift:18-22` — `promptAccessibility()` wraps
  `AXIsProcessTrustedWithOptions` with the prompt option set. It is the only such call
  in the repository and currently has **zero call sites**.
- `Nexus/Features/Tracker/TrackerService.swift:55-70` — `applyConfig(_:)` is the one
  place the tracker decides whether it may poll. When `Permissions.isAccessibilityTrusted`
  is false it stops polling, sets `status = .waitingForPermission`, logs, and calls
  `schedulePermissionRecheck()`. This is the branch the prompt belongs in, and the
  only branch the spec's trigger point can mean.
- `Nexus/Features/Tracker/TrackerService.swift:72-89` — `schedulePermissionRecheck()`
  re-reads `isAccessibilityTrusted` every 2 s. Anything added to the untrusted branch
  runs again on every tick and on every tracker-config change, so the prompt needs an
  idempotence guard rather than a bare call.
- `Nexus/Features/Tracker/TrackerService.swift:37-46` — `bootstrap()` subscribes to
  `config.$config.map(\.tracker)` and then calls `applyConfig` once, so the launch path
  reaches the untrusted branch immediately.
- `Nexus/App/AppEnvironment.swift:69` — `await tracker.bootstrap()` is the call that
  starts the tracker during `bootstrap()` (line 49).
- `Nexus/Features/Settings/TrackerSettingsForm.swift:22-36` — the Settings → Tracker
  status row. Today, while untrusted, it offers only "Open Accessibility Settings";
  that manual path must survive.
- `Nexus/Features/Tracker/Views/TrackerView.swift:87-104` — the in-window
  "Accessibility permission required" banner, whose only action is also
  "Open Settings". Same requirement.
- `project.yml:35-37` — the project declares exactly one target (`Nexus`, an
  application) and no test target, so this change is verified by inspection plus a
  manual launch, not by a unit test.

## Tasks
- [ ] Call `Permissions.promptAccessibility()` from the untrusted branch of `TrackerService.applyConfig` (`TrackerService.swift:62-68`), so the prompt is issued the first time the tracker would otherwise settle into `.waitingForPermission`
- [ ] Guard the call so it fires once per app launch and not again on each 2 s `schedulePermissionRecheck()` tick or on an unrelated tracker-config change
- [ ] Leave the `.waitingForPermission` status, the 2 s recheck, and both existing "Open Accessibility Settings" affordances unchanged, so a user who dismisses the system prompt still has a manual path
- [ ] Make the spec and the code name the same symbol — either point `.ea/spec/tracker.md:158-159` at `Permissions.promptAccessibility()` or add the `requestAccessibility()` name the spec uses; do not leave the two spellings in place
- [ ] Add a line to the `Permissions` section of `.ea/spec/architecture.md` only if the trigger point actually changes; the table already says `TrackerService.start()`, so no edit is expected there

## Acceptance
- [ ] `grep -rn "promptAccessibility" Nexus/` returns at least one call site, and that call site is in `Nexus/Features/Tracker/TrackerService.swift`
- [ ] Launching Nexus with Accessibility not yet granted for `site.easonsi.nexus` raises the macOS Accessibility prompt without the user opening System Settings first
- [ ] After that prompt is dismissed without granting, `status` stays `.waitingForPermission`, the 2 s recheck keeps running, and no second system prompt appears during the same launch
- [ ] Granting access from the prompt makes the tracker resume within 2 s through the existing `schedulePermissionRecheck()` path, with no change to that path
- [ ] `Settings → Tracker` still shows "Open Accessibility Settings" while untrusted, and `TrackerView` still shows its "Accessibility permission required" banner
- [ ] With `tracker.enabled = false` in `config.json`, no Accessibility prompt is issued
- [ ] `.ea/spec/tracker.md` and `Nexus/Core/Permissions.swift` name the same function for the AX request

## Boundaries
- Always: route the request through `Permissions.promptAccessibility()`, so the app has one place that knows about `kAXTrustedCheckOptionPrompt`
- Never: call `AXIsProcessTrustedWithOptions` directly from `TrackerService` — permission APIs stay behind `Permissions.swift`
- Never: prompt while `config.tracker.enabled` is false; the untrusted branch is only reached when the tracker is on, and that ordering must hold
- Never: block on the prompt. `promptAccessibility()` is non-blocking and returns the current trust value; the tracker keeps its recheck loop rather than waiting
- Ask: before moving the trigger point off `TrackerService.applyConfig` (for example to app launch in `AppDelegate`), because that would contradict the trigger point both spec files state
- Ask: before adding a second prompt surface in Settings — the existing button opens System Settings, and macOS shows its own prompt only a limited number of times
