# Architecture

## Overview
**EA Nexus** — macOS menu bar toolkit (Pomodoro timer, image uploader, time tracker).

- **Platform**: macOS (Menu Bar interaction)
- **Data/Config**: `~/.ea/nexus/`
- **Tech Stack**: Electron + Vite + React + TypeScript
- **Package Manager**: pnpm (enforced via `preinstall` hook + `engines`)
- **Architecture**: Main-Process-as-Source-of-Truth, modular features
- **UX Pattern**: Tray Popover (Menubar Icon → Click → Floating Frameless Window)

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
│   │   ├── PermissionManager.ts # macOS accessibility permission
│   │   └── Logger.ts           # electron-log wrapper
│   ├── features/
│   │   ├── pomodoro/           # Timer + stats
│   │   ├── tracker/            # Auto window tracking
│   │   ├── uploader/           # Image upload to GitHub
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
