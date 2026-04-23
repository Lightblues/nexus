# Changelog

## Unreleased — Command Palette

### New
- **Global command palette**: `Cmd+Shift+Space` opens a Raycast-style launcher. Fuzzy search, ↑/↓ + Enter keyboard nav, live subtitles showing pomodoro state. (ADR-009, ADR-010)
- **URL scheme `nexus://`**: Other apps can trigger Nexus commands via `nexus://command/<id>?args=…`. Registered via `electron-builder.yml` → `protocols` and `app.setAsDefaultProtocolClient`.
- **Pomodoro commands**: `pomodoro.toggle` (smart start/pause/resume), `pomodoro.start`, `pomodoro.pause`, `pomodoro.resume`, `pomodoro.finishEarly`, `pomodoro.exit`.
- **Config**: new `hotkey.palette` key (Electron Accelerator syntax) with hot-reload.

### Files Changed
```
New:
  src/main/core/CommandRegistry.ts
  src/main/core/PaletteWindow.ts
  src/main/core/GlobalHotkey.ts
  src/main/core/UrlSchemeHandler.ts
  src/main/features/pomodoro/commands.ts
  src/main/features/palette/{index,palette.ipc}.ts
  src/renderer/src/features/palette/PaletteView.tsx
  .ea/spec/palette.md

Modified:
  src/shared/types.ts            — HotkeyConfig, CommandItem
  src/shared/ipc.ts              — IPC.palette.*
  src/preload/index.ts           — palette.{list,execute,close,onOpened}
  src/renderer/src/env.d.ts      — palette API types
  src/renderer/src/App.tsx       — #/palette route
  src/main/core/{index,ConfigManager}.ts
  src/main/features/pomodoro/index.ts — registerPomodoroCommands
  src/main/index.ts              — palette/hotkey/URL wiring
  resources/default-config.yaml  — hotkey block
  electron-builder.yml           — protocols: nexus
  .ea/spec/{spec,architecture,decisions}.md
```

---

## v0.4.0 (2026-04-16) — Architecture Refactor

### P0 Fixes
- **IPC listener memory leak**: All preload event listeners (`onTick`, `onStatus`, `onFinished`, `onImageDropped`) now return cleanup functions. Renderer components call cleanup in `useEffect` return. (ADR-005)
- **Pomodoro history data bloat**: Auto-archive sessions older than 90 days to `~/.ea/nexus/archive/pomodoro-{YYYY}.json`. Active store stays bounded. `getAllSessions()` merges for long-range views. (ADR-004)

### P1 Fixes
- **Shared type system**: Created `src/shared/types.ts` — single source of truth for all cross-process interfaces. Eliminated duplicate type definitions across ~20 files. Added `@shared` alias in electron-vite + tsconfig. (ADR-002)
- **IPC type safety**: Created `src/shared/ipc.ts` — 47 channel names as `as const` constants. Preload + all `*.ipc.ts` handlers import from shared. Typo → compile error. (ADR-003)
- **Window type detection**: Replaced fragile `window.innerWidth > 500` with pure URL-hash routing. (ADR-006)

### P2 Improvements
- **ErrorBoundary**: Added React ErrorBoundary component wrapping each feature view independently. One view crash doesn't kill others. Fallback with error message + Retry button.
- **Pomodoro Edit Modal**: Unified idle + running/paused editing into a single modal. Idle state shows compact one-line summary (project · tags). Tags area scrollable for large tag lists. Esc key and backdrop click to close. (ADR-007)
- **Uploader UX**: Compression controls collapsed by default behind "▸ Compression (X% saved)" toggle. Reduces popup clutter.

### Infrastructure
- **pnpm enforcement**: Added `preinstall` hook, `engines`, `packageManager`, `pnpm.onlyBuiltDependencies`. Removed `npm run` from scripts. (ADR-008)
- **Removed `get-windows`**: Dependency was unused (tracker uses AppleScript). Saves native rebuild time and package size. (ADR-001)

### Files Changed (summary)
```
New:
  src/shared/types.ts          — shared interfaces
  src/shared/ipc.ts            — IPC channel constants
  src/renderer/src/components/ErrorBoundary.tsx

Modified (key files):
  electron.vite.config.ts      — @shared alias
  tsconfig.node.json           — paths + include shared
  tsconfig.web.json            — paths + include shared
  package.json                 — pnpm enforcement, removed get-windows
  src/preload/index.ts         — imports from @shared, cleanup returns
  src/renderer/src/env.d.ts    — imports from @shared, cleanup types
  src/renderer/src/App.tsx     — ErrorBoundary, hash-only routing
  src/main/core/DataManager.ts — auto-archiving, getAllSessions()
  src/main/core/PathManager.ts — archiveDir
  src/main/features/*/         — shared type imports, IPC constants
  src/renderer/src/features/*/ — shared type imports, listener cleanup
```
