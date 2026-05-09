---
id: nexus-007
title: Implement global command palette with Ctrl+Space activation
status: done
priority: high
estimate: L
labels: [feature, palette, ux]
---

## Objective
Add a global command palette (similar to Raycast/VSCode) as the primary interaction entry point for Nexus. Activated via Ctrl+Space, supports fuzzy command matching, and provides an extensible command system.

## Context
- UI reference: Raycast command palette
- Global shortcut: `Ctrl+Space` (avoids conflicts with Cmd+Space Spotlight, Opt+Space Raycast)
- Pomodoro IPC commands (start, pause, toggle)
- Design decision: integrate into Nexus rather than using Raycast extensions for extensibility

## Tasks
- [x] Register global shortcut `Ctrl+Space` to activate palette window
- [x] Build command palette UI with fuzzy search/matching
- [x] Implement Pomodoro commands (start from idle, toggle pause/continue from focus)
- [x] Add "Open main window" command (replaces tray icon as primary navigation)
- [x] List available commands below input for discoverability
- [x] Add icon in palette (bottom-left) linking to main window

## Acceptance
- [x] Ctrl+Space opens palette from anywhere on macOS
- [x] Typing filters commands with fuzzy matching
- [x] Pomodoro start/toggle commands execute correctly from palette
- [x] Palette dismisses after command execution
- [x] Commands are discoverable via listing in the palette UI
