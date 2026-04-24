# Architecture

## Overview
**Nexus** — macOS menu bar toolkit (Pomodoro timer, image uploader, time tracker).

- **Platform**: macOS (Menu Bar interaction)
- **Bundle ID**: `site.easonsi.nexus`
- **Data/Config**: `~/.ea/nexus/`
- **Tech Stack**: Electron + Vite + React + TypeScript
- **Package Manager**: pnpm (enforced via `preinstall` hook + `engines`)
- **Architecture**: Main-Process-as-Source-of-Truth, modular features
- **UX Pattern**: Tray Popover (Menubar Icon → Click → Floating Frameless Window)
- **Distribution**: Homebrew cask via [`lightblues/homebrew-tap`](https://github.com/Lightblues/homebrew-tap)

## Directory Structure

```
src/
├── shared/                     # Cross-process shared code
│   ├── types.ts                # All shared interfaces (single source of truth)
│   └── ipc.ts                  # IPC channel name constants (type-safe)
├── main/
│   ├── core/                   # Infrastructure
│   │   ├── index.ts
│   │   ├── ConfigManager.ts    # YAML config with hot-reload (fs.watch)
│   │   ├── DataManager.ts      # electron-store + auto-archiving
│   │   ├── PathManager.ts      # ~/.ea/nexus/ paths
│   │   ├── TrayManager.ts      # Icon, title, click, file drop
│   │   ├── PopupWindow.ts      # Frameless popover
│   │   ├── MainWindow.ts       # Standard window (stats/settings/tracker)
│   │   ├── PaletteWindow.ts    # Frameless centered command palette
│   │   ├── GlobalHotkey.ts     # electron globalShortcut wrapper
│   │   ├── UrlSchemeHandler.ts # nexus:// protocol → CommandRegistry
│   │   ├── CommandRegistry.ts  # Single table of commands (palette + URL share)
│   │   ├── PermissionManager.ts # macOS accessibility permission
│   │   └── Logger.ts           # electron-log wrapper
│   ├── features/
│   │   ├── pomodoro/           # Timer + stats + commands
│   │   ├── tracker/            # Auto window tracking
│   │   ├── uploader/           # Image upload to GitHub
│   │   ├── palette/            # Command palette IPC
│   │   └── settings/           # Config editor
│   └── index.ts                # Entry: init core → register IPC → start services
├── preload/
│   └── index.ts                # contextBridge API (imports from @shared)
└── renderer/
    └── src/
        ├── env.d.ts            # Window.api types (imports from @shared)
        ├── components/         # Button, Card, ErrorBoundary
        ├── features/           # Feature UI modules
        └── App.tsx             # View router (hash-based)
```

## Shared Type System (`src/shared/`)

All interfaces shared across main/preload/renderer are defined once in `src/shared/types.ts`. Both tsconfig files include `src/shared/` and define path alias `@shared/*`.

**Alias config** (`electron.vite.config.ts` + `tsconfig.*.json`):
```typescript
resolve: { alias: { '@shared': resolve(__dirname, 'src/shared') } }
```

Feature-specific main-process-only types (e.g., `Buffer`-based `ImageMetaMain`) remain in their feature `types.ts` and re-export shared types.

## IPC Type Safety (`src/shared/ipc.ts`)

All IPC channel names defined as `as const` object:
```typescript
export const IPC = {
  pomodoro: { start: 'pomodoro:start', pause: 'pomodoro:pause', ... },
  stats:    { getToday: 'stats:get-today', ... },
  config:   { get: 'config:get', ... },
  tracker:  { getStatus: 'tracker:get-status', ... },
  uploader: { upload: 'uploader:upload', imageDropped: 'uploader:image-dropped', ... },
  window:   { openStats: 'window:open-stats', openSettings: 'window:open-settings' },
} as const
```
Both preload and `*.ipc.ts` handlers import from `@shared/ipc`. Renaming/deleting a channel → compile-time error on both sides.

## Data & Configuration

### Config (`~/.ea/nexus/config.yaml`)
- Library: `js-yaml`
- Hot-reload: `fs.watch()` + debounce → `config:updated` event
- Merge with defaults on load (missing keys get default values)

### Data (`~/.ea/nexus/data.json`)
- Library: `electron-store`
- Contains: pomodoro stats + metadata (projects, tags, lastSession)
- **Auto-archiving**: Sessions older than 90 days moved to `~/.ea/nexus/archive/pomodoro-{YYYY}.json` on app startup. Prevents unbounded growth of the main data file.
- `getAllSessions()` merges active + archived for long-range views (activity calendar)

### Logging (`~/.ea/nexus/logs/main.log`)
- Library: `electron-log`

## Window Architecture

### PopupWindow (Tray Popover)
- Frameless, transparent, always-on-top, visible on all workspaces
- Hide on blur
- Positioned centered below tray icon
- Views: Dashboard → Pomodoro / Uploader (state-based routing)

### MainWindow
- Standard frame, resizable (900×600 default, 700×400 min)
- Sidebar navigation: Statistics / Time Tracker / Settings
- Hash-based routing (`#/stats`, `#/tracker`, `#/settings`)
- **Window type detection**: Purely URL-hash-based (no `innerWidth` heuristic). PopupWindow loads without hash → dashboard. MainWindow always loads with `#/stats` etc.

### Tray
- Left click: toggle popup
- Right click: context menu (Show Main Window / About / Quit)
- File drop: capture image → trigger uploader
- Title: idle=empty, pomodoro running=countdown ` 24:59`

## Error Handling

### ErrorBoundary (`src/renderer/src/components/ErrorBoundary.tsx`)
- React class component wrapping each feature view independently
- One view crash doesn't affect others
- Fallback: error message + Retry button
- Wrapped at: Popup (PomodoroView, UploaderView) and MainWindow (StatsView, TrackerView, SettingsView)

### IPC Listener Cleanup
All preload `ipcRenderer.on()` listeners return cleanup functions. Renderer components call cleanup in `useEffect` return to prevent memory leaks on remount.

```typescript
// preload pattern
onTick: (callback): (() => void) => {
  const handler = (_event, seconds) => callback(seconds)
  ipcRenderer.on(IPC.pomodoro.tick, handler)
  return () => ipcRenderer.removeListener(IPC.pomodoro.tick, handler)
}

// renderer pattern
useEffect(() => {
  const cleanup = window.api.pomodoro.onTick(...)
  return cleanup
}, [])
```

## Distribution & CI

### Install
```bash
brew install --cask lightblues/tap/nexus
```

### Build & Release Pipeline (`build.yml`)
Tag-triggered single workflow handles the full release cycle:

```
git tag nexus-vX.Y.Z && git push --tags
    ↓
build job (macos-latest):
  pnpm install → pnpm build → electron-builder --mac --arm64/x64
  electron-builder applies ad-hoc codesign via mac.identity: '-'
    ↓
release job (ubuntu-latest):
  Create GitHub Release with DMGs
  Compute sha256 from downloaded artifacts
  Push version + sha256 bump to lightblues/homebrew-tap/Casks/nexus.rb
    ↓
brew upgrade --cask nexus picks up new version
```

### Code Signing (no Apple Developer ID)
- **Ad-hoc codesign**: `electron-builder.yml` → `mac.identity: '-'` delegates to `@electron/osx-sign`, which signs nested frameworks/helpers inside-out (correct for Electron's bundle structure). Do **not** use `codesign --deep` manually — it signs outside-in and breaks the nested signature chain. (ADR-011)
- **Quarantine strip**: Homebrew cask `postflight` runs `xattr -dr com.apple.quarantine` so users don't see the Gatekeeper "cannot verify developer" dialog.
- **Consequence**: App launches cleanly on Apple Silicon and Intel without developer account. Users must trust the tap.

### Homebrew Tap (`lightblues/homebrew-tap`)
- Cask definition: `Casks/nexus.rb` — architecture-aware (`arch arm: "arm64", intel: "x64"`), per-arch sha256.
- Auto-bump: `build.yml` release job pushes cask updates via `TAP_PUSH_TOKEN` secret (fine-grained PAT, Contents:write on `homebrew-tap`).
- Fallback: `update-tap.yml` (`workflow_dispatch` only) for manual re-runs.
- One tap can host multiple casks/formulae for future projects.

### Secrets
| Secret | Repo | Purpose |
|--------|------|---------|
| `TAP_PUSH_TOKEN` | `Lightblues/nexus` | Fine-grained PAT (Contents:write on `homebrew-tap`). Used by release job to push cask updates. |
