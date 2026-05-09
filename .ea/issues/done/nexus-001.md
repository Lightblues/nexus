---
id: nexus-001
title: Fix IPC listener memory leak in preload and renderer
status: done
priority: urgent
estimate: M
labels: [bugfix, p0, stability]
---

## Objective
Fix memory leak caused by IPC listeners never being removed. All `ipcRenderer.on()` calls accumulate handlers on every component re-mount, eventually causing crashes in long-running sessions.

## Context
- `src/preload/index.ts` — all IPC bridge definitions (onTick, onStatus, etc.)
- `src/renderer/src/features/pomodoro/PomodoroView.tsx` — subscribes to pomodoro events
- `src/renderer/src/features/uploader/UploaderView.tsx` — subscribes to upload events
- `src/renderer/src/App.tsx` — top-level event subscriptions

## Tasks
- [x] Refactor all `ipcRenderer.on()` wrappers in preload to return cleanup functions
- [x] Update PomodoroView useEffect to call cleanup on unmount
- [x] Update UploaderView useEffect to call cleanup on unmount
- [x] Update App.tsx useEffect to call cleanup on unmount

## Acceptance
- [x] Every `onX` API in preload returns `() => void` cleanup function
- [x] All renderer useEffect hooks invoke cleanup in their return function
- [x] No listener accumulation after repeated component mount/unmount cycles
