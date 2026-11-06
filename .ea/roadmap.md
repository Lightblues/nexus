# Roadmap

nexus is the Mac-side assistant of the ea system: it senses what the user does on the Mac, acts on the Mac for him, and is the way outside agents (baton's steward, intake, Paseo agents) reach the Mac, as iris is for the browser. Proposal and reasoning: [log/2026-10-30-positioning.md](log/2026-10-30-positioning.md) (accepted 2026-10-30, except the relay, round 5, which is deferred). What the code does now: [docs/README.md](docs/README.md). Stages are rounds, numbered as in the proposal and taken in order; each is released as a patch (v1.3.2, v1.3.3, …) while nexus is moving fast.

## Done

- 2026-06: Swift rewrite (v1.0 → v1.2.3): pomodoro, app tracker, palette, uploader; standard macOS data layout (SADR-015).
- 2026-10-27/28: sync (v1.3.0, v1.3.1): server `services/server` at `nexus.easonsi.site`, `Packages/NexusSync`, app wiring nexus-018, export to intake through sonar. Two Macs converged; the settings overwrite on first contact fixed in v1.3.1 ([log](log/2026-10-27-sync.md)).
- Round 1: foundation, what later rounds stand on, no new features (2026-10-31). Development on devcloud, builds on CI, rolling beta (2026-10-30, SADR-018; nexus-003, 010, 011, 012): every push to `main` is built, launched, and DMG-checked on `macos-15`, signed with a stable self-signed identity, and published as the `nexus@beta` cask; `scripts/beta.sh install` keeps a Mac on it (xh-mini-m1 is the test Mac). Permissions survive upgrades (2026-10-30): the stable identity, and the Accessibility prompt on first start (nexus-002); checked by the user on the beta. Users on the server (2026-10-30, SADR-019): `users` and `keys` tables, every record owned by a user, the existing keys are the owner's; `npm run admin` adds users and keys; no login yet. Docs layout (2026-10-31): `AGENTS.md` (with `CLAUDE.md` a symlink), `docs/README.md` as the index, decisions in `log/decisions.md` with the SADR numbers kept, every `docs/` page checked against the code, Electron-era and pre-v1.2 pages and the migration script removed (the `legacy/electron` tag keeps them), `.ea/report/` folded into `log/`. Tests (2026-10-30, nexus-013): `NexusTests` (28 tests of pure logic, hosted in an app that starts no services) runs on every push before the build. Open fixes: nexus-009, 014, 015 (2026-10-30); nexus-005 and 007 (2026-10-31: `enrichApps` is the only gate, with an old two-app default upgraded; `uploader.enabled` and `showPopoverOnComplete` take effect); fresh-Mac first contact no longer seeds projects and tags (the starter catalog is gone, 2026-10-31). nexus-004 moved to round 2's op registry, nexus-006 and 008 to round 2's review.
- 2026-10-31: the data becomes visible (SADR-020, [log](log/2026-10-31-data.md)): tracker fixes (no lock-screen or sleep time, editor projects from the folder), settings in `nexus.db` (`config.json` imported once), server day summaries with categories, the read API, the `nexus` CLI (`cli/`, `.ea/docs/cli.md`) and skill as a reader of the server, not of the app (round 2 item), the web app at `/app` (round 3), intake keeping day summaries instead of raw tracker rows (round 4 item).
- Round 3: web, landing page and app (2026-10-31): `/` landing page, `/login` with a key and a read-only session cookie, `/app` Today / day / rows / History / Devices, installable (manifest, service worker); server aggregates are the day summaries (`.ea/docs/web.md`, `.ea/docs/sync.md` → Day summaries, Read API).

## Round 2: agent-native review and agent surface (now)

Done when: the review is written up as a log entry and a decision, the palette and `nexus://` run the same operations from one `CommandRegistry`, and `nexus doctor` and the web app's Devices page show each Mac's version, sync state, last error, and permissions.

- [ ] Review, iris style: every surface, command, setting, and record kind gets keep / fold / drop against "serves the user on the Mac, or agents from outside"; output a log entry and a decision. Takes in nexus-006 (sessions are edited through the CLI, not the web app) and nexus-008.
- [ ] One op registry: `CommandRegistry` as the single list of operations (id, description, typed arguments, result, `dangerous`), shared by the palette and `nexus://` (nexus-004).
- [x] `nexus` CLI and skill (2026-10-31, SADR-020): today, days, records, devices, categories, `config get/set`, doctor; npm publishing was the user's step (`@lightblues/nexus` 0.1.0, published by hand on 2026-10-31). Ops on a Mac (`run <op>`) wait for the relay (round 5).
- [ ] Self-diagnosis: each Mac reports version, sync state, last error, and permissions to the server, shown by `nexus doctor` and the Devices page (today they show only the last push and activity).

## Round 4: data flow into the system (next)

Done when: baton's daily summary reads nexus day summaries, and a pomodoro session started on a forge issue or a baton thread carries that id out through the export.

- [x] Aggregates in the export (`day_summary`) (2026-10-31, SADR-020): intake's `sync-nexus` keeps them instead of raw tracker rows.
- [ ] baton's daily summary reads them (change in baton).
- [ ] Pomodoro tasks from forge issues in progress and baton `doing.md` threads; the issue id flows out with the session.

## Round 5: Mac relay

Deferred by the user; needs open question 1 settled first.

- [ ] The app holds a WebSocket to the nexus server (iris's relay pattern: device tokens, `read` / `control` levels, liveness, `/devices`). `read`: context now, today's time, calendar today. `control`: notify, pomodoro start / stop, add a reminder, run a Shortcut, screenshot. sonar gets a `mac_*` connector. Ops from round 2 are the methods.

## Later

- Web: screenshots on the landing page; a check on the installed iPhone app (left from round 3).
- Casks: `postflight` is deprecated in Homebrew 7 (warning on install).
- Palette "Ask": the current context (app, selection, file, URL) handed to baton's steward or a Paseo agent; baton's inbox in the palette (open question 2).
- On-device AI: OCR of a screenshot, summaries of a day without sending titles out (open question 3).
- Upload history sync; actions from the web app through the relay.

## Log

- [2026-04-30 macOS WindowServer](log/2026-04-30-macos-windowserver.md): the Electron tracker's osascript polling as one trigger of a WindowServer stall, and its fixes.
- [2026-10-27 sync](log/2026-10-27-sync.md): the sync server, `NexusSync`, the app wiring, and the v1.3.0 / v1.3.1 rollout to two Macs.
- [2026-10-30 positioning](log/2026-10-30-positioning.md): nexus as the Mac-side assistant; data flow, agent surface, web app; the rounds of this roadmap.
- [2026-10-31 data](log/2026-10-31-data.md): tracker fixes, settings in `nexus.db`, day summaries, the CLI and the web app (SADR-020).

## Open questions

1. **Mac relay**: in nexus (proposed) or in intake (intake roadmap item 4)? Deferred by the user.
2. **Palette as an agent entry**: drop the "scoped to Nexus actions" non-goal? "Ask" to whom?
3. **macOS floor**: raise it (13) for on-device models (26+), or keep on-device AI optional?

Decided 2026-10-30: window titles and URLs sync and export as now (personal data behind the user's own key); the web app is read-only; one patch release per round.
