---
id: nexus-002
title: Fix Pomodoro history data bloat with auto-archive
status: done
priority: urgent
estimate: M
labels: [bugfix, p0, performance]
---

## Objective
Pomodoro session history grows unbounded, causing performance degradation over time. Implement automatic archival of old sessions to keep active data small.

## Context
- `src/main/core/DataManager.ts` — handles session persistence
- `src/main/core/PathManager.ts` — manages data file paths
- `src/main/features/pomodoro/StatsService.ts` — reads session data for stats
- Data location: `~/.ea/nexus/`

## Tasks
- [x] Add auto-archive mechanism: move sessions older than 90 days to yearly archive files (`~/.ea/nexus/archive/pomodoro-YYYY.json`)
- [x] Implement deduplication during archive writes
- [x] Add `getAllSessions()` method that merges active + archived data
- [x] Update StatsService activity calendar to use `getAllSessions()`
- [x] Add `archiveDir` to PathManager and auto-create in `ensureDirectories()`

## Acceptance
- [x] Sessions older than 90 days are automatically archived on app startup
- [x] Archive files are deduplicated by session ID
- [x] Activity calendar still shows full history spanning archived data
- [x] Active data file stays bounded in size
