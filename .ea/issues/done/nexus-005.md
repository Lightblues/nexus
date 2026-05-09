---
id: nexus-005
title: Fix Pomodoro edit page overflow and improve UX
status: done
priority: medium
estimate: M
labels: [bugfix, ui, pomodoro]
---

## Objective
When tags are numerous, the Pomodoro edit page overflows its container without scrolling, making it completely inoperable. Also improve general edit UX.

## Context
- Pomodoro edit page component (tag editing UI)
- "Tap to edit" section in Pomodoro start flow

## Tasks
- [x] Fix overflow: add scroll support when tags exceed container bounds
- [x] Reduce font size for better density
- [x] Add Esc keyboard shortcut to exit editing
- [x] Unify edit logic with the "tap to edit" section in Pomodoro start flow

## Acceptance
- [x] Edit page is scrollable when content exceeds container
- [x] Pressing Esc closes the edit view
- [x] Edit UI is consistent between session edit and pre-start edit
