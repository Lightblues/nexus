---
id: nexus-006
title: Implement auto-break transition and confetti celebration on focus end
status: done
priority: medium
estimate: M
labels: [feature, pomodoro, ux]
---

## Objective
Improve Pomodoro workflow: automatically enter break when focus session ends (no manual tap needed), and trigger Raycast confetti effect as a celebration/reward signal.

## Context
- Pomodoro state machine (focus → break transition)
- Raycast CLI integration (`open raycast://extensions/...`)
- Concern: confetti should not disrupt active typing

## Tasks
- [x] Auto-transition from focus end → break start without user interaction
- [x] Integrate Raycast confetti trigger on focus session completion
- [x] Ensure confetti does not interrupt keyboard input

## Acceptance
- [x] Focus session completion automatically starts break timer
- [x] Confetti visual fires on focus completion
- [x] User's active typing is not interrupted by the confetti trigger
