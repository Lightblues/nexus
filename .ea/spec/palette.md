# Command Palette

Raycast-style global launcher for triggering Nexus actions — both from a hotkey
UI and from external URL-scheme calls.

## Dual invocation surfaces, one source of truth

```
         ┌────────────────────────┐
Hotkey → │  PaletteWindow (UI)    │ ─┐
         └────────────────────────┘  │
                                     ├──→  CommandRegistry  ──→  Service calls
  nexus://command/… ──────────────────┘     (single table)       (PomodoroService, …)
```

Each feature registers commands in `CommandRegistry` on startup. Palette UI and
URL-scheme handler are **read-only consumers** — adding a command requires no
changes in either input layer.

## Global Hotkey

- Default: `CommandOrControl+Shift+Space` (configurable via `config.yaml`)
- Rejected alternatives:
  - `Cmd+Space` — Spotlight
  - `Option+Space` — reserved for Raycast
  - `Ctrl+Space` — conflicts with macOS "Select previous input source"
- Registered via Electron `globalShortcut`; hot-reloaded when
  `hotkey.palette` changes in config.
- Toggle behavior: if palette is visible, hide it; otherwise show it. Opening
  the palette always hides the tray popover to avoid two overlapping surfaces.

## PaletteWindow

Frameless, transparent, always-on-top (`screen-saver` level so it floats above
full-screen apps), 640×420, centered horizontally and at ~22% from the top of
the active display's work area (matches Raycast's visual position).

Loaded via URL hash `#/palette` — the existing renderer handles it alongside
`#/stats`, `#/settings`, `#/tracker` (ADR-006 routing rule preserved).

## PaletteView (renderer)

| Area | Behavior |
|------|----------|
| Search input | Autofocused on show; text is selected so the next keystroke replaces the previous query |
| Results | Substring-first scoring, subsequence fallback; fields ranked: title > group > keywords > subtitle |
| Keyboard | ↑/↓ navigate, `Enter` run, `Esc` close; hover selects |
| Footer | Home icon (→ `window.openMain`) · toast messages (success/failure) · result count · key hints |
| Discoverability | Empty query → all currently-applicable commands (VSCode command-palette style) |

## URL Scheme

Shape: `nexus://command/<id>?<args>`

Examples:
- `nexus://command/pomodoro.toggle`
- `nexus://command/pomodoro.start?project=work`

Registration:
- `app.setAsDefaultProtocolClient('nexus')` at startup
- `Info.plist` declared via `electron-builder.yml` → `protocols`
- Handled on `open-url` (macOS) and `second-instance` (cold start / other platforms)
- Single-instance lock required so repeat invocations reuse the running app

Security note: commands flagged `dangerous: true` should require a UI
confirmation when triggered from `url-scheme` (not yet implemented; future
work).

## Registered commands (initial)

| ID | When | Action |
|----|------|--------|
| `pomodoro.toggle` | always | Smart: idle→start, running→pause, paused→resume |
| `pomodoro.start` | idle | Start a focus session |
| `pomodoro.pause` | running | Pause current session |
| `pomodoro.resume` | paused | Resume paused session |
| `pomodoro.finishEarly` | running/paused (work) | Record session and move to finished |
| `pomodoro.exit` | non-idle | Discard current session (dangerous) |
| `window.openMain` | always | Open main window (default route = stats) |
| `window.openStats` | always | Open main window at `/stats` |
| `window.openTracker` | always | Open main window at `/tracker` |
| `window.openSettings` | always | Open main window at `/settings` |

Subtitles are dynamic — e.g. `pomodoro.toggle` shows `running · 12:34 · click to pause`.

## Extending

1. Create `features/<feature>/commands.ts`
2. Export `register<Feature>Commands()` that calls `commandRegistry.registerMany([...])`
3. Call it from `main/index.ts` before `registerPaletteIPC()`

Commands inherit existing service state — they are not a new abstraction, just
a second entry point.
