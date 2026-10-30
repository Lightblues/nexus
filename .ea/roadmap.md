# Roadmap

nexus is the Mac-side assistant of the ea system: it senses what the user does on the Mac, acts on the Mac for him, and is the way outside agents (baton's steward, intake, Paseo agents) reach the Mac, as iris is for the browser. Proposal and reasoning: [log/2026-10-30-positioning.md](log/2026-10-30-positioning.md) (proposed). What the code does now: [docs/README.md](docs/README.md).

Status: accepted 2026-10-30, except the relay (round 5), which is deferred. Rounds are in order; each is released as a patch (v1.3.2, v1.3.3, …) while nexus is moving fast.

## Done

- 2026-06: Swift rewrite (v1.0 → v1.2.3): pomodoro, app tracker, palette, uploader; standard macOS data layout (SADR-015).
- 2026-10-27/28: sync (v1.3.0, v1.3.1): server `services/server` at `nexus.easonsi.site`, `Packages/NexusSync`, app wiring nexus-018, export to intake through sonar. Two Macs converged; the settings overwrite on first contact fixed in v1.3.1 ([log/2026-10-27-sync.md](log/2026-10-27-sync.md)).
- 2026-10-31: the data becomes visible (SADR-020, [log/2026-10-31-data.md](log/2026-10-31-data.md)): tracker fixes (no lock-screen or sleep time, editor projects from the folder), settings in `nexus.db` (`config.json` imported once), server day summaries with categories, the read API, the `nexus` CLI (`cli/`) and skill, the web app at `/app`, intake keeping day summaries instead of raw tracker rows.

## 1. Foundation (in progress)

What later rounds stand on. No new features.

1. ~~**Development on devcloud, builds on CI, rolling beta.**~~ Done 2026-10-30 (SADR-018): every push to `main` is built, launched, and DMG-checked on `macos-15`, signed with a stable self-signed identity, and published as the `nexus@beta` cask; `scripts/beta.sh install` keeps a Mac on it (xh-mini-m1 is the test Mac). nexus-003, 010, 011, 012 done.
2. ~~**Permissions survive upgrades.**~~ Done 2026-10-30: the stable identity, and the Accessibility prompt on first start (nexus-002); checked by the user on the beta.
3. ~~**Users on the server.**~~ Done 2026-10-30 (SADR-019): `users` and `keys` tables, every record owned by a user, the existing keys are the owner's; `npm run admin` adds users and keys. No login yet.
4. ~~**Docs layout.**~~ Done 2026-10-31: `AGENTS.md` (with `CLAUDE.md` a symlink), `docs/README.md` as the index, decisions in `log/decisions.md` with the SADR numbers kept, every `docs/` page checked against the code, Electron-era and pre-v1.2 pages and the migration script removed (the `legacy/electron` tag keeps them), `.ea/report/` folded into `log/`.
5. ~~**Tests.**~~ Done 2026-10-30: `NexusTests` (28 tests of pure logic, hosted in an app that starts no services) runs on every push before the build (nexus-013).
6. **Open fixes.** nexus-009, 014, 015 done 2026-10-30; nexus-005 done 2026-10-31 (`enrichApps` is the only gate, and an old two-app default is upgraded to the new list). Still: nexus-007; nexus-004 goes into round 2's op registry; nexus-006 and 008 into round 2's review (sessions are edited through the CLI, not the web app). Fresh-Mac first contact: seeded default projects and tags lose to the server's copies. The casks' `postflight` is deprecated in Homebrew 7 (warning on install).

## 2. Agent-native review and agent surface

1. **Review**, iris style: every surface, command, setting, and record kind gets keep / fold / drop against "serves the user on the Mac, or agents from outside"; output a log entry and a decision.
2. **One op registry**: `CommandRegistry` as the single list of operations (id, description, typed arguments, result, `dangerous`), shared by the palette and `nexus://`.
3. ~~**`nexus` CLI and skill**~~: done 2026-10-31 as a reader of the server, not of the app (`cli/`, `.ea/docs/cli.md`): today, days, records, devices, categories, `config get/set`, doctor. Ops on a Mac (`run <op>`) wait for the relay (round 5); npm publishing is the user's step.
4. **Self-diagnosis**: each Mac reports version, sync state, last error, and permissions to the server, shown by `nexus doctor` and the Devices page (today they show only the last push and activity).

## 3. ~~Web: landing page and app~~

Done 2026-10-31 (`.ea/docs/web.md`): `/` landing page, `/login` with a key and a read-only session cookie, `/app` Today / day / rows / History / Devices, installable (manifest, service worker). Server aggregates are the day summaries (`.ea/docs/sync.md` → Day summaries, Read API). Still: screenshots on the landing page; a check on the installed iPhone app.

## 4. Data flow into the system

1. ~~Aggregates in the export (`day_summary`)~~: done 2026-10-31; intake's `sync-nexus` keeps them instead of raw tracker rows. Still: baton's daily summary reads them (change in baton).
2. Pomodoro tasks from forge issues in progress and baton `doing.md` threads; the issue id flows out with the session.

## 5. Mac relay

The app holds a WebSocket to the nexus server (iris's relay pattern: device tokens, `read` / `control` levels, liveness, `/devices`). `read`: context now, today's time, calendar today. `control`: notify, pomodoro start / stop, add a reminder, run a Shortcut, screenshot. sonar gets a `mac_*` connector. Ops from round 2 are the methods. Needs open question 1 settled first.

## Later

- Palette "Ask": the current context (app, selection, file, URL) handed to baton's steward or a Paseo agent; baton's inbox in the palette (open question 3).
- On-device AI: OCR of a screenshot, summaries of a day without sending titles out (open question 6).
- Upload history sync; actions from the web app through the relay.

## Open questions

1. Mac relay in nexus (proposed) or in intake (intake roadmap item 4)? Deferred by the user.
2. Palette as an agent entry (drop the "scoped to Nexus actions" non-goal)? "Ask" to whom?
3. Raise the macOS floor (13) for on-device models (26+), or keep on-device AI optional?

Decided 2026-10-30: window titles and URLs sync and export as now (personal data behind the user's own key); the web app is read-only; one patch release per round.
