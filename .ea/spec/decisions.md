# Architecture Decisions

## ADR-001: AppleScript over get-windows for window tracking
**Date**: 2025  
**Status**: Accepted

**Context**: `get-windows` uses a standalone Swift binary that requires its own Accessibility permission entry. In production builds, macOS treats each binary separately, causing repeated permission prompts.

**Decision**: Use AppleScript via `osascript` which inherits the main Electron app's Accessibility permission. No additional binaries to package.

**Consequence**: Removed `get-windows` from dependencies. Slightly slower per-poll (AppleScript overhead ~50ms) but acceptable at 5s intervals.

---

## ADR-002: Shared type system (`src/shared/`)
**Date**: 2026-04  
**Status**: Accepted

**Context**: The same interfaces (PomodoroStatus, SessionRecord, UploaderConfig, etc.) were duplicated in 3+ places: main process types, preload/index.ts (300+ lines of interface defs), and renderer components (local re-declarations like `UploaderConfigLocal`). Changes to one copy would silently diverge from others.

**Decision**: Create `src/shared/types.ts` as single source of truth. Configure `@shared` alias in electron-vite + tsconfig for all three processes. Main-process-only types (`Buffer`-based) kept in feature `types.ts` files.

**Consequence**: ~20 files updated. Preload reduced from 300+ lines to pure imports. Renderer components import types directly. Compile-time safety across process boundaries.

---

## ADR-003: IPC channel constants (`src/shared/ipc.ts`)
**Date**: 2026-04  
**Status**: Accepted

**Context**: 47 IPC channels were magic strings scattered across preload and `*.ipc.ts` files. Typo in channel name → silent runtime failure with no compile-time warning.

**Decision**: Define all channels as `as const` object in `src/shared/ipc.ts`. Both preload and main handlers import `IPC.pomodoro.start` instead of `'pomodoro:start'`.

**Consequence**: Rename/delete a channel → TypeScript error on both sides. Minor verbosity increase (`IPC.pomodoro.start` vs string literal) but worth the safety.

---

## ADR-004: Pomodoro data auto-archiving
**Date**: 2026-04  
**Status**: Accepted

**Context**: All pomodoro sessions stored in `data.json` as one array. `electron-store` serializes entire store on every `.set()`. At 2000+ sessions: slow writes, growing memory usage.

**Decision**: On app startup, sessions older than 90 days auto-archived to `~/.ea/nexus/archive/pomodoro-{YYYY}.json`. Active store stays small. `getAllSessions()` merges active + archived for long-range views (activity calendar). Archive files are append-only with ID-based deduplication.

**Consequence**: Active store stays bounded (~90 days × ~10 sessions/day ≈ 900 records max). Historical data preserved and queryable. Tracker already used per-day files, so this aligns the pattern.

---

## ADR-005: IPC listener cleanup pattern
**Date**: 2026-04  
**Status**: Accepted

**Context**: Preload `ipcRenderer.on()` listeners didn't return cleanup functions. Every time a renderer component mounted, it registered new listeners without removing old ones. Repeated view switches → listener accumulation → memory leak → eventual crash.

**Decision**: All preload event listeners (`onTick`, `onStatus`, `onFinished`, `onImageDropped`) return `() => void` cleanup functions. Renderer `useEffect` calls cleanup on unmount.

**Consequence**: Fixed memory leak. Breaking change to preload API (return type `void` → `() => void`), updated `env.d.ts` accordingly.

---

## ADR-006: Window type detection via URL hash
**Date**: 2026-04  
**Status**: Accepted

**Context**: App.tsx used `window.innerWidth > 500` to distinguish PopupWindow from MainWindow. Fragile — would break if popup width config changed.

**Decision**: Purely hash-based detection. MainWindow always loads with `#/stats`, `#/settings`, or `#/tracker`. PopupWindow loads without hash → defaults to dashboard.

**Consequence**: Removed width heuristic. Deterministic routing regardless of window dimensions.

---

## ADR-007: Unified Edit Modal for Pomodoro session config
**Date**: 2026-04  
**Status**: Accepted

**Context**: Idle state had an inline project/tags/task editor that took ~120px of vertical space in the 320×400 popup, often causing scroll. Running/paused state had a separate Edit Modal. Two different UIs for the same data, duplicated rendering code.

**Decision**: Both idle and running/paused use the same Edit Modal (opened by clicking session info summary). Idle state shows a compact one-line summary card instead of inline forms. Tags area has `maxHeight: 100px` with scroll for large tag lists. Esc key and backdrop click close the modal.

**Consequence**: Cleaner idle state (ring + summary + Start button fits without scroll). Single code path for editing. Tags overflow handled gracefully.

---

## ADR-008: pnpm enforcement
**Date**: 2026-04  
**Status**: Accepted

**Context**: Mixed usage of npm/pnpm caused issues. `build:mac` script used `npm run build`. pnpm v10 defaults to blocking dependency postinstall scripts, causing Electron binary not to install.

**Decision**: 
- `preinstall` hook: `npx only-allow pnpm`
- `engines`: `pnpm >= 9`
- `packageManager`: `pnpm@10.12.1`
- `pnpm.onlyBuiltDependencies`: whitelist electron, esbuild, sharp, node-mac-permissions
- All scripts use `pnpm` instead of `npm run`

**Consequence**: `npm install` or `yarn install` → immediate error. Electron binary installs correctly via whitelisted postinstall scripts.
