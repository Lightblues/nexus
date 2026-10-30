# Roadmap

nexus is the Mac-side assistant of the ea system: it senses what the user does on the Mac, acts on the Mac for him, and is the way outside agents (baton's steward, intake, Paseo agents) reach the Mac, as iris is for the browser. Proposal and reasoning: [log/2026-10-30-positioning.md](log/2026-10-30-positioning.md) (proposed). What the code does now: [docs/spec.md](docs/spec.md).

Status: draft, 2026-10-30, waiting for the user's review. Rounds are in order; each is released when done (versioning is open question 5).

## Done

- 2026-06: Swift rewrite (v1.0 → v1.2.3): pomodoro, app tracker, palette, uploader; standard macOS data layout (SADR-015).
- 2026-10-27/28: sync (v1.3.0, v1.3.1): server `services/server` at `nexus.easonsi.site`, `Packages/NexusSync`, app wiring nexus-018, export to intake through sonar. Two Macs converged; the settings overwrite on first contact fixed in v1.3.1 ([log/2026-10-27-sync.md](log/2026-10-27-sync.md)).

## 1. Foundation

What later rounds stand on. No new features.

1. **Docs layout.** `AGENTS.md` (with `CLAUDE.md` a symlink), `docs/README.md` as the index (from `spec.md`), decisions to `log/decisions.md` with the SADR numbers kept, every `docs/` page checked against the code (`tracker.md` still describes the Electron JSON store).
2. **CI.** Build and test `main` on every push (nexus-010), launch the built app (nexus-003), strict codesign and lipo (nexus-011), mount the DMG (nexus-012), unit test target (nexus-013).
3. **Permissions survive upgrades.** A stable signing identity instead of ad-hoc, so the Accessibility grant is kept across Homebrew upgrades; the Accessibility prompt on first start (nexus-002).
4. **Open fixes.** Triage nexus-004 to 009, 014, 015: fix, fold into round 2, or close. Fresh-Mac first contact: seeded default projects and tags lose to the server's copies.

## 2. Agent-native review and agent surface

1. **Review**, iris style: every surface, command, setting, and record kind gets keep / fold / drop against "serves the user on the Mac, or agents from outside"; output a log entry and a decision.
2. **One op registry**: `CommandRegistry` as the single list of operations (id, description, typed arguments, result, `dangerous`), shared by the palette and `nexus://`.
3. **`nexus` CLI and skill**: status, today, sessions, ops, `run <op>`, talking to the running app; shipped with the cask.
4. **Self-diagnosis**: each Mac reports version, sync state, last error, and permissions to the server; `nexus doctor` locally.

## 3. Web: landing page and app

On the nexus server, like iris's web app, following the `pwa` skill.

1. `/` landing page (what it is, the brew command, screenshots); `/login` with a key and a session cookie.
2. `/app`: Today (sessions, time by project / app / domain, timeline), History, Devices (from round 2's reports). Installable on the iPhone.
3. Server aggregates (time per day by project, app, domain) on an API, used by the web app and by agents.

## 4. Data flow into the system

1. Aggregates in the export (`day_summary`), so intake and baton read a day in one call; baton's daily summary uses them (change in baton).
2. Pomodoro tasks from forge issues in progress and baton `doing.md` threads; the issue id flows out with the session.
3. Privacy tier for window titles and URLs, decided before the export grows (open question 2).

## 5. Mac relay

The app holds a WebSocket to the nexus server (iris's relay pattern: device tokens, `read` / `control` levels, liveness, `/devices`). `read`: context now, today's time, calendar today. `control`: notify, pomodoro start / stop, add a reminder, run a Shortcut, screenshot. sonar gets a `mac_*` connector. Ops from round 2 are the methods. Needs open question 1 settled first.

## Later

- Palette "Ask": the current context (app, selection, file, URL) handed to baton's steward or a Paseo agent; baton's inbox in the palette (open question 3).
- On-device AI: OCR of a screenshot, summaries of a day without sending titles out (open question 6).
- Upload history sync; actions from the web app through the relay.

## Open questions

1. Mac relay in nexus (proposed) or in intake (intake roadmap item 4)?
2. Privacy: sync window titles and URLs as now, or allowlist titles and export only aggregates?
3. Palette as an agent entry (drop the "scoped to Nexus actions" non-goal)? "Ask" to whom?
4. Web app edits: write sessions as a sync device, or read-only?
5. Versioning: a minor per round (as iris D001) or patches only (baton's convention for personal projects)?
6. Raise the macOS floor (13) for on-device models (26+), or keep on-device AI optional?
