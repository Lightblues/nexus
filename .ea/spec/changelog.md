# Changelog

## v0.5.1 (2026-04-24) — Fix ad-hoc codesign

### Fixes
- **Fix crash on launch**: v0.5.0 used `codesign --deep --sign -` via a custom `afterPack` hook, which signs Electron's nested bundles in the wrong order (outside-in), causing macOS dyld to reject the app with "different Team IDs". Replaced with `mac.identity: '-'` in `electron-builder.yml`, which delegates to `@electron/osx-sign` — the official Electron signing tool that correctly signs inside-out.
- Removed `build/after-pack.cjs` (broken hook).

---

## v0.5.0 (2026-04-24) — Rename + Homebrew Distribution

### Breaking
- **Renamed `EA Nexus` → `Nexus`**. App bundle is now `Nexus.app`, DMG is `Nexus-<ver>-<arch>.dmg`.
- **`appId` changed** `com.ea.nexus` → `site.easonsi.nexus`. ⚠️ macOS tracks Accessibility permission by `appId`, so existing users must **re-grant** Accessibility permission (System Settings → Privacy & Security → Accessibility → enable Nexus) for the Tracker to resume working. Pomodoro/Uploader are unaffected.
- **`package.json` name** `ea-nexus` → `nexus` (internal only, no user impact).

### New — Homebrew Distribution
- **Homebrew tap**: [`lightblues/homebrew-tap`](https://github.com/Lightblues/homebrew-tap). Install via:
  ```bash
  brew install --cask lightblues/tap/nexus
  ```
- **Ad-hoc codesign** (`build/after-pack.cjs`): since Nexus has no Apple Developer ID, the CI build applies `codesign --sign -` to the `.app` bundle. Without this, Apple Silicon macOS rejects the app with `killed: 9`.
- **Cask `postflight`** strips `com.apple.quarantine` so users don't see the "Apple could not verify" Gatekeeper dialog on first launch.
- **Auto cask bump** (`.github/workflows/update-tap.yml`): on every `nexus-v*` release, the workflow computes SHA256 of the published DMGs and commits a version/sha256 bump to `homebrew-tap/Casks/nexus.rb`. Requires `TAP_PUSH_TOKEN` secret (fine-grained PAT with Contents:write on `homebrew-tap`).

### Files Changed
```
New:
  build/after-pack.cjs                       — ad-hoc codesign hook
  .github/workflows/update-tap.yml           — auto cask bump

Modified:
  electron-builder.yml                       — afterPack hook wired in
  package.json                               — name, version, description
  .github/workflows/build.yml                — workflow/artifact/release names
  scripts/install-release.sh                 — APP_NAME/DMG_NAME
  resources/default-config.yaml              — comment
  src/main/core/{TrayManager,MainWindow,PermissionManager}.ts
  src/main/index.ts                          — logger messages
  src/main/features/uploader/GitHubUploader.ts
  src/renderer/index.html                    — <title>
  src/renderer/src/features/{dashboard,main,tracker}/*.tsx
  .ea/spec/{spec,architecture}.md, .ea/runs.sh
```

---

## Unreleased — Command Palette

### New
- **Global command palette**: `Cmd+Shift+Space` opens a Raycast-style launcher. Fuzzy search, ↑/↓ + Enter keyboard nav, live subtitles showing pomodoro state. (ADR-009, ADR-010)
- **URL scheme `nexus://`**: Other apps can trigger Nexus commands via `nexus://command/<id>?args=…`. Registered via `electron-builder.yml` → `protocols` and `app.setAsDefaultProtocolClient`.
- **Pomodoro commands**: `pomodoro.toggle` (smart start/pause/resume), `pomodoro.start`, `pomodoro.pause`, `pomodoro.resume`, `pomodoro.finishEarly`, `pomodoro.exit`.
- **Window commands**: `window.openMain` / `openStats` / `openTracker` / `openSettings` — also surfaced as a home icon in the palette footer (click → main window).
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
  src/main/features/window/{index,commands}.ts
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
