---
schema_version: 1
id: nexus-008
title: Build the uploader popover the spec describes
status: todo
priority: high
estimate: M
labels: [uploader, popover, ui, feature-gap]
isolation: local
delivery: none
---

## Objective
Add the 320 × 400 uploader popover the spec describes and route every entry point — the
palette command and the status-item drop — to it, so dropping an image no longer brings
the whole main window forward.

## Context
- `.ea/spec/uploader.md:131-160` ("## UI (Popover)") — the 320 × 400 layout diagram plus
  the three bullets below it: `DropZoneView` drag/click/paste, a collapsed compression
  section, a path picker with a "+ New path" inline field, and an Upload button disabled
  while a request is in flight. This is the surface to build.
- `.ea/spec/uploader.md:20-26` ("## Pipelines", Pipeline B) — "Drag enters StatusItem
  button drop receiver → `DropReceiver.handleDrop(items)` →
  `UploaderService.pendingImage = bundle` → `showPopover()` → `UploaderPopoverView`
  observes `pendingImage` on appear → goes to preview state."
- `.ea/spec/uploader.md:162-167` ("## Commands") — the command is named
  `uploader.openPopover` ("Show popover in uploader view").
- `.ea/spec/architecture.md:75-82` ("## Target Layout") — the uploader's only view file is
  `Uploader/Views/UploaderPopoverView.swift`, which does not exist in the tree.
- `.ea/spec/architecture.md:286` — "`PopupWindow.ts` | `NSPopover` containing
  `NSHostingController`": the popover is the spec's general shape for feature popovers.
- `.ea/spec/architecture.md:296` — the spec's routing enum is
  `MainRoute { case stats, tracker, settings }`, with no `uploader` case. The code's four
  cases are drift, not a second sanctioned route.
- `Nexus/Features/MainWindow/MainRoute.swift:8` — `case uploader`, with label/icon at
  `:17` and `:26`. This is what makes the uploader a full-window destination.
- `Nexus/Features/MainWindow/MainWindowView.swift:21-23` and `:57` — the uploader sits in
  the sidebar "Tools" section and renders `UploaderView()` in the detail pane.
- `Nexus/Features/MainWindow/MainWindowController.swift:29-38` — `show()` sets
  `NSApp.setActivationPolicy(.regular)` (`:35`), calls `window.makeKeyAndOrderFront(nil)`
  (`:36`) and `NSApp.activate(ignoringOtherApps: true)` (`:37`). This is the code that
  brings the whole window forward on a drop.
- `Nexus/App/AppDelegate.swift:77-84` — `handleStatusItemDrop` stashes the pending batch
  and then calls `environment.mainWindow.show(route: .uploader)` (`:83`). This is the drop
  entry point to re-route.
- `Nexus/Features/Uploader/UploaderCommands.swift:10-22` — `uploader.open` ("Uploader:
  Open") → `mainWindow?.show(route: .uploader)` (`:20`). The spec's id is
  `uploader.openPopover`; whether to rename is a decision this issue must record.
- `Nexus/Features/Uploader/UploaderService.swift:12-15` — the stale doc comment that names
  `UploaderPopoverView`, and the `pendingImages: [PendingImage]?` batch slot the popover
  must consume; `:127-141` is the `setPending` / `takePending` read-once hand-off.
- `Nexus/Features/Uploader/Views/UploaderView.swift:21-80` — the existing batch UI and its
  pending-image wiring (`onAppear` at `:69-73`, `onChange(of: service.pendingImages?.count)`
  at `:74-76`). A popover must reuse this consume path so a drop still lands as a batch.
- `Nexus/App/AppDelegate.swift:49-73` — `installStatusItem()`, where `StatusItemDropView`
  is attached and the drop callback is wired (`:66-68`); `Nexus/Features/Uploader/StatusItemDropView.swift:19-30`
  is the receiver, whose callback delivers a multi-image payload.
- `Nexus/App/AppDelegate.swift:125-152` — the existing status-item `NSPopover` (pomodoro).
  `installPopover()` builds one popover with one fixed root view (`:126-137`), so a second
  popover surface for the uploader is a wiring decision: a second `NSPopover`, or one
  popover with a switchable root.
- `Nexus/Features/Pomodoro/Views/PomodoroPopoverView.swift:26` — the existing popover root
  is `.frame(width: 320, height: 400)`, the same size the uploader spec asks for; it is the
  layout precedent to follow.
- `Nexus/Features/Palette/PaletteController.swift:82-98` — the `NSHostingView`-in-a-panel
  precedent, if the uploader surface is built as a panel instead of a popover.
- `Nexus/App/AppEnvironment.swift:56-57` — `mainWindow.attach(environment:)` and
  `palette.attach(environment:)` run before any `await`; an uploader popover controller
  that needs the environment should be attached the same way.
- `project.yml:35-38` — one application target and no test target, so the acceptance checks
  below are a manual drop / palette run, not a unit test.

## Tasks
- [ ] Add `Nexus/Features/Uploader/Views/UploaderPopoverView.swift` with the layout at
      `.ea/spec/uploader.md:131-160`: drop zone, preview plus size delta, collapsed
      compression disclosure, path and filename, Upload button, recent-uploads strip
- [ ] Give the popover the spec's 320 × 400 content size, matching
      `PomodoroPopoverView.swift:26` and the `NSHostingController` frame in
      `AppDelegate.installPopover()` (`:133-134`)
- [ ] Route the status-item drop (`AppDelegate.handleStatusItemDrop`, `:77-84`) to the
      popover instead of `mainWindow.show(route: .uploader)`, so a drop no longer activates
      Nexus or orders the main window front
- [ ] Route the uploader command to the popover; record whether the id stays
      `uploader.open` or becomes the spec's `uploader.openPopover`, and keep the registry
      entry the single source for both the palette and `nexus://`
- [ ] Reuse the pending-image hand-off unchanged: `UploaderService.setPending(_:)` /
      `takePending()` (`UploaderService.swift:127-141`) plus the read-once consume in the
      popover's `onAppear` and on `pendingImages?.count` change (`UploaderView.swift:69-76`)
- [ ] Decide the fate of the `MainRoute.uploader` window route — the spec's enum at
      `.ea/spec/architecture.md:296` has no such case, so removing it is the
      spec-aligned option and keeping it needs a reason — and make `MainRoute.swift:8`,
      `MainWindowView.swift:21-23`, `:57` agree with the decision
- [ ] Reuse `UploaderService`, `UploaderRepository`, `ImageCompressor` and the existing
      batch item model; the popover is a second presentation of the same behaviour, not a
      second uploader implementation
- [ ] Update the stale doc comment at `UploaderService.swift:12-13` to name the view that
      actually consumes `pendingImages`
- [ ] Update `.ea/spec/uploader.md:162-167` if the command id changes, and `:20-26` if the
      pipeline's `showPopover()` step is named differently in the code
- [ ] Update `.ea/spec/architecture.md:296` if the shipped `MainRoute` keeps its
      `uploader` case, so the routing table and the enum agree either way

## Acceptance
- [ ] `grep -rn "UploaderPopoverView" Nexus/` resolves to a real SwiftUI view at
      `Nexus/Features/Uploader/Views/UploaderPopoverView.swift`, not only to a doc comment
- [ ] Dropping an image on the menu-bar icon shows the popover anchored to the status item
      and does **not** bring the main window forward; `NSApp.setActivationPolicy(.regular)`
      and `NSApp.activate(ignoringOtherApps:)` are not reached on the drop path
- [ ] The dropped image appears in the popover's preview state without a second user
      action, through the existing `takePending()` read-once hand-off
- [ ] The palette entry for the uploader command opens the same popover, not the main
      window route
- [ ] The popover's content size is 320 × 400, matching `.ea/spec/uploader.md:133-153` and
      the pomodoro popover
- [ ] An upload started from the popover writes the same `upload_history` row and copies
      the same CDN URL as one started from the window route — verified by uploading the
      same file both ways and comparing the recorded row
- [ ] Dismissing the popover and reopening it does not duplicate a previously consumed
      pending image
- [ ] A second drop while the popover is already open lands in the same batch slot rather
      than being ignored
- [ ] `.ea/spec/uploader.md` "## UI (Popover)" and "## Pipelines" describe the shipped
      surface, and `MainRoute` / `MainWindowView` agree with the decision recorded for the
      window route

## Boundaries
- Always: reuse `UploaderService`, `UploaderRepository` and `ImageCompressor`; the popover
  must not grow a parallel upload path, because the DB row, thumbnail cache and clipboard
  write all live in `UploaderService.upload` (`UploaderService.swift:56-103`)
- Always: keep the status-item drop working while the popover is open — the receiver
  delivers multi-image payloads (`StatusItemDropView.swift:19-21`) and the batch cap is
  existing behaviour
- Always: keep the popover non-activating the way the pomodoro popover is
  (`AppDelegate.swift:146-153`); the "summon → use → dismiss" flow the spec describes
  depends on not stealing focus
- Never: leave `MainRoute.uploader` in place while the spec's routing enum and the
  "## Target Layout" both describe the uploader as a popover only — the two must not
  disagree after this change
- Never: duplicate the compression controls' state — the quality slider and format picker
  must keep coming from `ConfigService` defaults (`UploaderView.adoptConfigDefaults`,
  `UploaderView.swift:461`) so the popover and the window cannot show different defaults
- Never: change `UploaderService.pendingImages` from a batch to a single image; the
  drop receiver and the `uploader.uploadClipboard` command both feed it a batch
- Ask: whether `MainRoute.uploader` should be removed entirely or kept as a secondary
  destination. The spec's enum has no such case, so removal is the aligned choice, but it
  also removes the sidebar entry and any `nexus://`-style path that reaches it
- Ask: whether the command id should change from `uploader.open` to the spec's
  `uploader.openPopover`. Renaming it breaks any existing `nexus://command/uploader.open`
  link or Shortcut, so the choice needs to be explicit
- Ask: before adding a third popover/panel surface type — the app already has `NSPopover`
  for the pomodoro and `NSPanel` for the palette, and a third shape multiplies the
  dismissal and focus bugs each one carries
