---
id: nexus-004
title: Fix window type detection to use URL hash instead of innerWidth
status: done
priority: high
estimate: S
labels: [bugfix, p1, ui]
---

## Objective
Window type detection using `window.innerWidth > 500` is unreliable and causes UI confusion in edge cases. Replace with deterministic URL hash-based detection.

## Context
- `src/renderer/src/App.tsx` — window type routing logic

## Tasks
- [x] Remove `window.innerWidth` based detection logic
- [x] Implement hash-based routing: `#/stats`, `#/settings`, `#/tracker` → MainWindow
- [x] Default (no hash) → Popup/dashboard view

## Acceptance
- [x] Window type is determined solely by URL hash
- [x] No UI glitches when resizing windows
- [x] Main window routes and popup route work correctly
