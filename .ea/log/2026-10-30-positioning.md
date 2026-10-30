# 2026-10-30: nexus positioning, data flow, agent-native, web

Status: proposed (2026-10-30), waiting for the user's review. Plan: [`../roadmap.md`](../roadmap.md).

Participants: Eason + Cursor agent (on devcloud_cpu). Inputs: the user's notes of 2026-10-30; iris `.ea/roadmap.md` and `.ea/log/2026-10-30-positioning-review.md` (the method reused here); baton `.ea/roadmap.md` and `research/building-with-ai/`; intake `.ea/log/2026-10-23-product-boundaries.md` and `.ea/roadmap.md` (item 4, device relay); the 2026-10-27 sync rollout ([2026-10-27-sync.md](2026-10-27-sync.md)).

## Why now

nexus was built feature by feature (Electron, then the Swift rewrite, then sync) without a stated place in the ea system. iris and baton now each have one (iris: the browser-side agent and relay; baton: the top layer that holds context and watches agents), and nexus's docs predate the shared `.ea/` layout. The rollout of 2026-10-27 also showed the cost: diagnosing the second Mac needed a Paseo agent reading SQLite by hand, and each Homebrew upgrade drops the Accessibility grant.

## 1. Position

**nexus is the Mac-side assistant of the ea system**: it senses what the user does on the Mac, acts on the Mac for him, and is the way outside agents reach the Mac. It is to the Mac what iris is to the browser.

Two roles, the same split iris uses:

1. **For the user, on the Mac**: time (pomodoro, app tracking), the palette as the entry from any app, small native tools (uploader).
2. **For agents, from outside**: a sensor (what the user did and is doing) and an actuator (calendar, reminders, notifications, Shortcuts, the pomodoro) that baton's steward, intake, and Paseo agents call through the nexus server.

Every feature should serve one of the two; the review in section 3 applies that test.

## 2. What only a native app can do

What the web apps (baton, intake, forge, iris's web app) and iOS PWAs cannot:

| Capability | Native means | Today |
|---|---|---|
| Passive, continuous sensing | AX API: frontmost app, window title, file and project (editor titles), browser URL (Apple Events); idle detection | tracker, ~100k records |
| An entry from anywhere | global hotkey, non-activating panel over any app; the current app's selection, clipboard, Finder selection, a screenshot | palette (Nexus commands only) |
| Presence | menu bar item, native notifications with actions, Focus mode | pomodoro popover |
| System data and automation | EventKit (calendar, reminders), Shortcuts, AppleScript / Apple Events, the file system | none |
| On-device processing | Vision (OCR), speech, Apple's on-device models (macOS 26+), local-only data | none |
| Private by default | raw titles and URLs can stay on the Mac; only what is needed leaves | everything syncs today |

The differentiator is the combination: always on, knows the current context, can act locally. Nothing here needs nexus to host a chat UI; agents live in Paseo, baton, intake, and iris.

## 3. Agent-native review (to run, iris style)

Go through every surface, command, setting, and record kind with one question: does it serve the user on the Mac, or agents from outside? Verdict per item: keep / fold / drop, as in iris's review. Candidates already visible:

- **One op registry.** `CommandRegistry` is already shared by the palette and `nexus://command/<id>`. Make it the single list of operations, each with an id, a description, typed arguments, a result, and a `dangerous` flag, and expose the same list on every surface: palette, URL scheme, a `nexus` CLI on the Mac, and the relay (section 4). intake's op registry (`api/op.ts`) is the model.
- **A CLI and a skill.** `nexus status | today | sessions | ops | run <op>` talking to the running app (local socket or URL scheme with a reply), shipped in the app bundle and linked by the cask; a `nexus` skill that says when to use it. Agents on the Mac (Cursor, Claude Code, Paseo) then read "what is the user doing" and drive the pomodoro without SQLite.
- **Self-diagnosis.** Each Mac reports its version, sync state, last error, and permissions (Accessibility, Automation per browser) to the server; a `nexus doctor` op returns the same locally. This replaces the hand-run SQLite and log reading of 2026-10-27.
- **Palette as the agent entry.** Today a non-goal says the palette stays scoped to Nexus actions. Revisit: "Ask" with the current context (app, selection, file, URL) sent to baton's steward or a Paseo agent, and baton's inbox count and items reachable from the palette. nexus does not run the agent; it hands context over and shows the answer or a link.
- **Settings and data that explain themselves.** `/export/kinds` descriptions that say what each field means; errors that name the condition (nexus-015); docs that match the code (`tracker.md` still describes the Electron JSON store).
- **Keep thin.** The uploader stays a small tool (no development beyond fixes); new small tools land as ops, not as windows.

## 4. Data flow

Today ([sync.md](../docs/sync.md)): each Mac ↔ nexus server (records, last write wins); server `/export/changes` → sonar `export_changes app=nexus` → intake `sync-nexus` → `raw` (`source=nexus`); settings are never exported.

Proposed, in the system's direction (intake is a consumer, baton is the top layer, B010 in baton):

- **Out, as facts agents can use.** Raw tracker rows are too many for an agent to read. The server adds aggregates (time per day by project, app, and domain; focus sessions with their task) on an API and in the export (`day_summary` kind), so intake and baton read a day in one call. baton's daily summary (`steward-daily`, `personal/daily/`) gets "where my time went" from it (change in baton).
- **In, from the system.** The pomodoro's task picker offers forge issues in progress and baton `doing.md` threads, so a focus session is tied to an issue id; that link flows back out with the session. Time per issue and per repository then comes for free.
- **Through, from agents to the Mac: the Mac relay.** The app keeps a WebSocket to the nexus server (iris's relay pattern: device token, `read` and `control` levels, `/devices`, ping liveness). Methods: `read` for context now, today's time, calendar today; `control` for notify, start or stop a pomodoro, add a reminder, run a Shortcut, screenshot. sonar gets a `mac_*` connector, as it has `browser_*` through iris. This is intake roadmap item 4 (device relay with EventKit, Shortcuts, osascript), moved to nexus because intake no longer owns device-side work (its `src/devices` was deleted on 2026-10-24).
- **Privacy tiers.** Window titles and URLs are the sensitive part. Options: keep syncing everything (personal use, as settings do), or sync titles only for an allowlist and export only aggregates. To decide before the export grows.

## 5. Web: landing page and app

Same shape as iris's web app (iris `.ea/docs/server.md` § Web app; the stack of forge's and iris's `services/web`: React, Vite, Tailwind, served by the server) and the `pwa` skill (a tool app).

- **`/`**: landing page: what nexus is, `brew install --cask lightblues/tap/nexus`, screenshots, how sync works. No key needed.
- **`/login`**: paste a key, session cookie (iris's flow). One user.
- **`/app`**: Today (focus sessions and time by project, app, and domain, a timeline); History (days, weeks, search by project or app); Devices (each Mac: version, last sync, permissions, errors, online through the relay); later, actions through the relay (start a pomodoro on the Mac at the desk). Installable as a PWA on the iPhone.
- Settings are not shown in the web app (they hold the GitHub token).

## 6. Engineering that the rest needs

- Docs in the shared `.ea/` layout: `AGENTS.md` (with `CLAUDE.md` a symlink), `.ea/roadmap.md`, `.ea/docs/README.md`, decisions moved to `.ea/log/decisions.md` keeping the SADR numbers, docs checked against the code.
- CI on every push to `main`, a launch test, strict codesign and lipo checks, DMG inspection, a unit test target (nexus-010, 003, 011, 012, 013).
- **A stable signing identity**, so the Accessibility grant survives upgrades (each ad-hoc signed release is a new signer; Homebrew warns "signer changed"), plus the Accessibility prompt on first start (nexus-002).
- The fresh-Mac first contact: seeded default projects and tags should lose to the server's copies.

## Open questions

1. Is the Mac relay nexus's (proposed) or intake's (intake roadmap item 4)? Needs a line in intake's roadmap and baton's project page.
2. Privacy tier for titles and URLs (section 4).
3. Does the palette become an agent entry (drop the non-goal), and to whom does "Ask" go: baton's steward, or a Paseo agent chosen per request?
4. Edits from the web app (fix a session): the web app as a sync device writing through `/api/sync/push`, or read-only?
5. Versioning: a minor per planned round (iris D001) or patches only (baton's convention for personal projects, 2026-10-30); the user decides.
6. On-device models need macOS 26; nexus targets macOS 13. Raise the floor, or keep on-device AI optional?
