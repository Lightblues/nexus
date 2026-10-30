# Nexus docs

Nexus is the Mac side of the ea system. The menu bar app records what the user does on
each Mac (pomodoro sessions, the app and project in front) and acts on the Mac (pomodoro,
palette, image upload). The server holds every Mac's data, turns tracker rows into day
summaries, and serves them to the `nexus` CLI, the web app, and intake. Plan:
[../roadmap.md](../roadmap.md); positioning: [../log/2026-10-30-positioning.md](../log/2026-10-30-positioning.md).

## Pages

| File | Content |
|------|---------|
| [architecture.md](architecture.md) | The three parts, app target layout, lifecycle, data layout, distribution |
| [pomodoro.md](pomodoro.md) | Pomodoro state machine, popover, stats |
| [tracker.md](tracker.md) | How time is recorded: polling, idle and lock rules, enrichment |
| [uploader.md](uploader.md) | ImageIO compression, GitHub upload, drop targets |
| [palette.md](palette.md) | NSPanel palette, global hotkey, `nexus://`, CommandRegistry |
| [sync.md](sync.md) | Sync: record kinds, the server's HTTP contract, users and keys, day summaries, export, deploy |
| [cli.md](cli.md) | The `nexus` CLI and its skill |
| [web.md](web.md) | The web app: landing page, login, Today, History, Devices |
| [pitfalls.md](pitfalls.md) | Traps already hit; read before reusing a pattern |
| [../log/decisions.md](../log/decisions.md) | Decisions (SADR-001 .. SADR-020), append-only |

The Electron app that preceded the Swift rewrite is at the `legacy/electron` git tag.

## Quick reference

| Item | Value |
|---|---|
| Bundle ID | `site.easonsi.nexus` (frozen) |
| Min macOS | 13.0; universal binary |
| Data | `~/Library/Application Support/site.easonsi.nexus/nexus.db` (records and settings), `sync.json`; `~/Library/Caches/...`; `~/Library/Logs/.../main.log` |
| Server | `https://nexus.easonsi.site` (`services/server`, devcloud) |
| Install | `brew install --cask lightblues/tap/nexus`; beta: `scripts/beta.sh install` |

## Coding style

The repository style applies (compact, typed, minimal docstrings, English). Swift: no
force-unwraps outside tests; `ObservableObject` (macOS 13); keep files under 300 lines.

## Non-goals

Cross-platform; feature parity with Raycast or Alfred; a plugin API.
