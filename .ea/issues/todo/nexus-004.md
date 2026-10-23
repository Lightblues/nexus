---
schema_version: 1
id: nexus-004
title: Require confirmation for dangerous commands from `nexus://` URLs
status: todo
priority: high
estimate: S
labels: [palette, url-scheme, safety, feature-gap]
isolation: local
delivery: none
---

## Objective
Replace the log-and-run branch in the `nexus://` URL handler with a confirmation step for
commands flagged `dangerous`, so `nexus://command/app.quit` and
`nexus://command/pomodoro.exit` cannot fire from a link, a Shortcut or a Raycast
quicklink without the user agreeing.

## Context
- `.ea/spec/palette.md:169-201` ("## URL Scheme") — the normative handler. Its sample at
  `:196` reads `if cmd.dangerous { /* TODO: confirm UI — same TODO as Electron */ }`, so
  the spec requires a confirmation step but deliberately leaves the surface open.
- `.ea/spec/palette.md:216-217` — "Single-instance lock is automatic for macOS bundled
  apps — re-launching the already-running `Nexus.app` simply forwards the URL via Apple
  Events." This is what makes the unguarded branch reachable from outside the app: any
  process that can call `open nexus://...` reaches the running handler.
- `Nexus/Core/URLScheme.swift:64-70` — the defect. The `if cmd.dangerous` branch only
  writes `Log.app.warn` and then falls through to `Task { await cmd.run() }`. This is the
  single code path this issue changes.
- `Nexus/Core/CommandRegistry.swift:16` — `let dangerous: Bool` on `Command`; `:26` and
  `:46` default it to `false`. `grep -rn "dangerous" Nexus/` shows it has exactly one
  reader: the URL handler above. That single reader is what this issue rewrites.
- `Nexus/Features/MainWindow/WindowCommands.swift:52-55` — `app.quit`, registered with
  `dangerous: true`.
- `Nexus/Features/Pomodoro/PomodoroCommands.swift:110-114` — `pomodoro.exit`, registered
  with `dangerous: true`. Its `run` discards the running session, which is why the
  confirmation matters beyond `app.quit`.
- `Nexus/App/AppEnvironment.swift:74-82` — the five `*Commands.register(...)` calls run
  before `URLSchemeHandler.shared.install()`, so by the time the handler can fire, the
  registry and every service behind these commands exist. A confirmation surface may
  assume the environment is live.
- `Nexus/App/AppDelegate.swift:125-152` — the app's only popover precedent
  (`installPopover()` / `togglePopover()`). `Nexus/Features/Palette/PalettePanel.swift`
  plus `Nexus/Features/Palette/PaletteController.swift:82-98` are the non-activating
  `NSPanel` precedent. There is **no `NSAlert` anywhere in the codebase**
  (`grep -rn "NSAlert" Nexus/` returns nothing), so the confirmation surface is new and
  should reuse one of these two shapes rather than inventing a third.
- `Nexus/App/AppDelegate.swift:146-153` — the comment explaining why the pomodoro popover
  deliberately does **not** call `NSApp.activate(ignoringOtherApps: true)`. A confirmation
  on the URL path faces the same choice and should not undo it.
- `Nexus/Features/MainWindow/MainWindowController.swift:18-38` — `show()` is the only
  place the app calls `NSApp.activate(ignoringOtherApps:)` (`:37`); a modal confirmation
  that needs key focus has to interact with that deliberately, because the whole point of
  the URL path is that it arrives while the user is looking at another app.
- `Nexus/Features/Palette/PaletteController.swift:54-73` — the click-outside dismissal
  pattern the non-activating panel already uses. A confirmation surface that follows the
  panel shape needs the same treatment so a stray outside click cannot be read as consent.
- `project.yml:35-38` — one application target and no test target, so the acceptance
  checks below are a manual URL dispatch, not a unit test.

## Tasks
- [ ] Make the `dangerous` branch in `URLSchemeHandler.dispatch(url:)`
      (`Nexus/Core/URLScheme.swift:64-70`) present a confirmation before `cmd.run()` is
      called, instead of logging and falling through
- [ ] Call `cmd.run()` only on an explicit affirmative; a dismissal, a stray outside
      click, or a surface that fails to appear must leave the command unrun and must not
      be treated as consent
- [ ] Reuse an existing presentation shape rather than adding a new one: either the
      status-item `NSPopover` pattern (`AppDelegate.swift:125-152`) or the non-activating
      panel pattern (`PaletteController.swift:82-98` plus its click-outside monitors at
      `:54-73`). State in the PR which one and why
- [ ] Name the command in the confirmation, so the user can tell "Quit Nexus" from
      "Exit focus session" without knowing the command id
- [ ] Decide and record the behaviour when the confirmation cannot be presented (no active
      screen, app hidden, surface creation fails): the safe default is to not run the
      command and to log the refusal
- [ ] Delete the `TODO Phase 4.x` comment at `URLScheme.swift:64-65` and update
      `.ea/spec/palette.md:196` so the spec no longer shows the confirmation as a TODO

## Acceptance
- [ ] `open nexus://command/app.quit` against a running Nexus does not terminate the app
      until the user confirms; dismissing the confirmation leaves the app running
- [ ] `open nexus://command/pomodoro.exit` while a focus session is running does not
      discard the session until the user confirms; dismissing it leaves the session
      running and its remaining time unchanged
- [ ] Confirming either command performs exactly the action the palette entry performs —
      the confirmation is a gate in front of `cmd.run()`, not a reimplementation
- [ ] A command registered with `dangerous: false` still runs immediately, with no new
      prompt (`grep -n "dangerous: true" Nexus/` lists only `app.quit` and
      `pomodoro.exit`)
- [ ] `grep -rn "dangerous" Nexus/` still shows exactly one reader of the flag, and that
      reader is the URL handler; the palette is not gated by it
- [ ] `.ea/spec/palette.md` "## URL Scheme" describes the confirmation as implemented
      behaviour and no longer contains the `TODO: confirm UI` comment
- [ ] The log line for a refused command is distinguishable from the log line for a
      confirmed one, so a refusal is auditable in `main.log`

## Boundaries
- Always: gate on `Command.dangerous`, the same flag the spec's handler keys off, so a
  newly registered dangerous command is covered without a second list to maintain
- Always: treat dismissal and non-presentation as refusal — the URL path can arrive with
  no user present, so "no answer" must never mean "yes"
- Always: run the command on the main actor, as the current handler does, so a confirmed
  `app.quit` / `pomodoro.exit` touches the same state the palette would
- Never: add a confirmation to the palette path — the palette is a user-driven surface
  where the user is already looking at the command they selected; only the externally
  triggered `nexus://` path is unguarded
- Never: call `NSApp.activate(ignoringOtherApps: true)` unconditionally just to make the
  confirmation visible — that is the window-stealing behaviour the app already avoids for
  the pomodoro popover (`AppDelegate.swift:146-153`)
- Never: block the main actor while waiting for an answer; the handler is `@MainActor` and
  a modal that spins the runloop there would freeze the status item
- Ask: before adding a "remember my choice" / always-allow setting — nothing in the spec
  asks for one, and it would let the original hole reopen permanently
- Ask: before extending `dangerous` to commands that are not currently flagged; that
  changes the command table, not just the URL handler
