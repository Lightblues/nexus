---
schema_version: 1
id: nexus-006
title: Add edit and delete for a recorded session
status: todo
priority: high
estimate: M
labels: [stats, sessions, crud, feature-gap]
isolation: local
delivery: none
---

## Objective
Give the Stats session list an edit and delete path backed by
`PomodoroRepository.update(_:)` plus a delete, so a session recorded with the wrong
project, tags or duration — or one started by mistake — can be corrected or removed
instead of staying permanent.

## Context
- `.ea/spec/pomodoro.md:173-177` ("### Session List") — the normative statement:
  `List(sessionsForDay) { session in SessionRow(session) }`, `SessionRow` opens
  `EditSessionSheet` for inline editing, and "Saves go through
  `PomodoroService.update(_:)` which writes to the store and updates
  `SessionHistoryService`." None of those three pieces exists in the code today.
- `.ea/spec/pomodoro.md:134-144` ("### EditSessionModal") — the editor the spec wants
  reused: a SwiftUI sheet (not a window), project `Menu` + "+ New" `TextField`, tag
  chips with `TextField("Add tag")`, single-line task `TextField`, tags scroll capped at
  `maxHeight: 100`.
- `.ea/spec/pomodoro.md:146-171` ("## Stats UI") — places `StatsView` and
  `ActivityCalendar` under `Features/Pomodoro/Views/`; on disk they live under
  `Nexus/Features/Stats/`. Recorded here because the issue touches the Stats surface,
  not because this task should move them.
- `Nexus/Features/Stats/StatsView.swift:6-27` — `StatsView`; `@EnvironmentObject var
  repo: PomodoroRepository` (line 7) is already injected, so the list can write without
  new plumbing. `sessionListCard` is stacked at line 22.
- `Nexus/Features/Stats/StatsView.swift:201-215` — `sessionListCard`. Renders a plain
  `VStack` of `SessionRow`s inside a `StatsCard`; there is no tap gesture, no selection
  binding, and no action closure, so the list is read-only by construction.
- `Nexus/Features/Stats/StatsView.swift:262-343` — `SessionRow`. Renders the kind dot,
  the `HH:mm – HH:mm` range, duration, project/tags/task and the orange "partial"
  capsule. Display-only: the struct has no callbacks and no `@State`.
- `Nexus/Features/Stats/StatsView.swift:195-197` — `loadDay()` calls
  `repo.sessions(on: selectedDate)` into `@State daySessions`. This is the reload point
  a save or delete must re-run, and `daySessions` is the only state the page owns.
- `Nexus/Features/Pomodoro/PomodoroRepository.swift:79-108` — `update(_ record:
  SessionRecord) async` already exists and writes kind, start/end, duration, project,
  task, `completed_fully` and re-inserts the tag rows. It has **no call site**:
  `grep -rn "\.update(" Nexus/` returns nothing. This is the write path to reach.
- `Nexus/Features/Pomodoro/PomodoroRepository.swift:124-134` — `sessions(on:)`, the
  query behind `daySessions`.
- `Nexus/Features/Pomodoro/PomodoroRepository.swift:27-56` — `refresh()` rebuilds the
  `@Published` projections (`lastSession`, `todayCount`, `todayDuration`, catalogs).
  `update(_:)` calls it at line 104, so a Stats edit also refreshes the popover's
  counters — no extra work needed there.
- `Nexus/Features/Pomodoro/PomodoroRepository.swift:243-292` — the only delete methods
  in the repository are `deleteProject` and `deleteTag`. There is **no delete for a
  session row**: `grep -rn "DELETE FROM pomodoro_sessions" Nexus/` returns nothing, so
  the delete half of this issue has to be added, not wired.
- `Nexus/Features/Pomodoro/PomodoroService.swift:105-108` — `updateDraftMetadata(_:)`
  is the only `update`-shaped method on the service, and it writes the *draft*
  (`repository.updateLastSessionMetadata`), not a persisted record. The spec's
  `PomodoroService.update(_:)` does not exist; the service's full method list is at
  lines 28, 34, 45, 56, 65, 74, 91, 100, 105.
- `Nexus/Features/Pomodoro/Views/EditSessionModal.swift:4-16` — the shared editor. Its
  initializer takes `metadata: SessionMetadata` plus `onSave`/`onCancel` closures, so it
  can already be driven from outside the popover; what it cannot express is the
  `SessionRecord`-only fields (kind, start/end, duration, `completedFully`).
- `Nexus/Features/Pomodoro/Views/PomodoroPopoverView.swift:27-35` — the only
  `EditSessionModal` call site: a `.sheet(isPresented: $showEditor)` bound to
  `pomodoro.draftMetadata`. This flow must keep working unchanged.
- `Nexus/Features/Pomodoro/PomodoroModels.swift:17-27` — `SessionRecord`: `let id`,
  `kind`, `startTime`, `endTime`, `duration`, then `var project`, `tags`, `task`,
  `completedFully`. `id`, `kind`, `startTime`, `endTime` and `duration` are `let`; an
  editor that touches duration has to construct a new value, and `update(_:)` writes
  start/end/duration together so the three must stay consistent.
- `Nexus/Features/MainWindow/WindowCommands.swift:20-26` — `window.openStats` routes to
  `.stats`, which is how a user reaches this page from the palette.
- `.ea/spec/pomodoro.md:154` and `:177` — both name `SessionHistoryService` as the
  active-plus-archived session source. No such type exists anywhere in `Nexus/`
  (`grep -rn "SessionHistoryService" Nexus/` returns nothing); the archived/active split
  was replaced by direct SQL over `pomodoro_sessions`. Do not create the type to satisfy
  the sentence — correct the sentence while aligning the save-path names.
- `project.yml:35-37` — one target (`Nexus`, an application) and no test target, so this
  change is verified by inspection plus a manual run, not by a unit test.

## Tasks
- [ ] Add a selection or tap affordance to the Stats session list so each `SessionRow` can open an editor for its own `SessionRecord` — the list is currently a bare `VStack` (`StatsView.swift:201-215`) with no interaction
- [ ] Let the editor carry a persisted `SessionRecord`, not only a pre-session `SessionMetadata`: either generalize `EditSessionModal` or add a sibling, and keep the popover's existing draft sheet (`PomodoroPopoverView.swift:27-35`) working unchanged
- [ ] Route the save through a `PomodoroService.update(_:)` so the symbol the spec names exists, and let it call the already-written `PomodoroRepository.update(_:)` (`PomodoroRepository.swift:79-108`) — that method needs its first call site
- [ ] Add a delete path for a session: a repository method (mirroring `deleteProject` at `PomodoroRepository.swift:264`) plus the service wrapper, and expose it from the editor or the row
- [ ] Decide and implement how a duration edit keeps `startTime` / `endTime` / `duration` consistent, since `update(_:)` writes all three together (`PomodoroRepository.swift:82-96`)
- [ ] Re-run `loadDay()` (`StatsView.swift:195-197`) after a save or delete so the list reflects the change without a relaunch, and keep `StatsCard`/`SessionRow` styling intact
- [ ] Align `.ea/spec/pomodoro.md:175-177` with the names the implementation lands on (`PomodoroService.update(_:)`, `EditSessionSheet`) so spec and code use one spelling

## Acceptance
- [ ] Selecting a session in the Stats list opens an editor pre-filled with that row's project, tags and task
- [ ] Saving writes through to SQLite: the row re-renders with the new values immediately, and the change survives a relaunch
- [ ] Deleting a session removes it from the list, and a fresh `sessions(on:)` for that day no longer returns it
- [ ] `grep -rn "\.update(" Nexus/` returns at least one call site, and it reaches `PomodoroRepository.update(_:)` through `PomodoroService`
- [ ] `grep -rn "DELETE FROM pomodoro_sessions" Nexus/` returns a real delete path that Stats can reach
- [ ] The popover's pre-session editor still opens from `PomodoroPopoverView.swift:27-35` and still saves via `updateDraftMetadata(_:)`
- [ ] A break session (`shortBreak` / `longBreak`) in the list opens, edits and deletes without crashing — the row is not work-only
- [ ] Editing a session refreshes the repository's `@Published` projections, so the popover's today counters and the Database card stay consistent
- [ ] `.ea/spec/pomodoro.md` and the code name the same save and editor symbols

## Boundaries
- Always: write through `PomodoroRepository` (`insert` / `update` / the new delete) so the `@Published` projections refresh in one place (`PomodoroRepository.swift:5`, `:27-56`)
- Always: keep `startTime`, `endTime` and `duration` mutually consistent on save — `update(_:)` persists all three verbatim
- Never: mutate `SessionRecord` in the view and leave the store stale; the list must reload from `sessions(on:)` rather than trusting local state
- Never: rewrite `EditSessionModal`'s `SessionMetadata` interface in a way that breaks the popover's draft flow (`PomodoroPopoverView.swift:28-34`)
- Never: add a second session-list rendering — the existing `SessionRow` and `StatsCard` are the components to extend
- Ask: whether the editor should expose duration/start/end at all, or only project/tags/task as `EditSessionModal` does today — the candidate names "duration" but the spec's `EditSessionSheet` does not
- Ask: whether deleting needs a confirmation step; the app has no `NSAlert` and no SwiftUI `.alert`/`.confirmationDialog` anywhere, so this would be a new UI form (see nexus-004)
- Ask: whether editing should be reachable for archived/historical days only or for today as well — the page has one `selectedDate` (`StatsView.swift:9`) and no archive boundary
