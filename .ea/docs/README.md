# Nexus docs

These pages describe what the code does now. Nexus is the Mac side of the ea system. The menu bar app records what the user does on each Mac (pomodoro sessions, the app and project in front) and acts on the Mac (pomodoro, palette, image upload), and watches it (memory pressure). The server holds every Mac's data, turns tracker rows into day summaries, and serves them to the `nexus` CLI, the web app, and intake. Plan: [../roadmap.md](../roadmap.md); positioning: [../log/2026-10-30-positioning.md](../log/2026-10-30-positioning.md).

| File | Contents | Update when |
|---|---|---|
| [architecture.md](architecture.md) | The three parts, app target layout, lifecycle, data layout, distribution | A part, target, data path, or the build and release flow changes |
| [pomodoro.md](pomodoro.md) | Pomodoro state machine, popover, stats | The timer's states, the popover, or the stats change |
| [tracker.md](tracker.md) | How time is recorded: polling, idle and lock rules, enrichment | The tracker's pipeline, rules, or enriched fields change |
| [uploader.md](uploader.md) | ImageIO compression, GitHub upload, drop targets | Compression, the upload path, the uploader UI, or its config changes |
| [memory.md](memory.md) | Memory watch: pressure notifications naming the top processes, baton machine events | The sampler, the notification rule, the event format, or its settings change |
| [palette.md](palette.md) | NSPanel palette, global hotkey, `nexus://`, CommandRegistry | The palette, the hotkey, the URL scheme, or a registered command changes |
| [sync.md](sync.md) | Sync: record kinds, the server's HTTP contract, users and keys, day summaries, export, deploy | A record kind, route, merge rule, summary field, export kind, or the deploy changes |
| [cli.md](cli.md) | The `nexus` CLI and its skill | A command, flag, or the CLI's release changes |
| [web.md](web.md) | The web app: landing page, login, Today, History, Devices | A page, route, or the login changes |
| [pitfalls.md](pitfalls.md) | Traps already hit; read before reusing a pattern | A new trap is hit and fixed |
| [../log/decisions.md](../log/decisions.md) | Decisions (SADR-001 .. SADR-021), append-only | A trade-off is settled |

The Electron app that preceded the Swift rewrite is at the `legacy/electron` git tag.

## Quick reference

| Item | Value |
|---|---|
| Bundle ID | `site.easonsi.nexus` (frozen) |
| Min macOS | 13.0; universal binary |
| Data | `~/Library/Application Support/site.easonsi.nexus/nexus.db` (records and settings), `sync.json`; `~/Library/Caches/...`; `~/Library/Logs/.../main.log`; `~/.baton/machine-events/` (memory events for baton) |
| Server | `https://nexus.easonsi.site` (`services/server`, devcloud) |
| Install | `brew install --cask lightblues/tap/nexus`; beta: `scripts/beta.sh install` |

## Coding style

The repository style applies (compact, typed, minimal docstrings, English). Swift: no force-unwraps outside tests; `ObservableObject` (macOS 13); keep files under 300 lines.

## Non-goals

Cross-platform; feature parity with Raycast or Alfred; a plugin API.
