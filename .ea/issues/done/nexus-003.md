---
id: nexus-003
title: Extract shared types module to eliminate cross-process type duplication
status: done
priority: high
estimate: L
labels: [refactor, p1, dx]
---

## Objective
Type definitions for cross-process interfaces (Pomodoro, Stats, Config, Tracker, Uploader, Settings) are duplicated across main/preload/renderer, causing drift and bugs. Consolidate into a single shared module.

## Context
- `src/shared/types.ts` — new shared types file (~250 lines)
- `electron.vite.config.ts` — build config for all three processes
- `tsconfig.node.json` / `tsconfig.web.json` — TypeScript path config
- ~20 files across `src/main/core/`, `src/main/features/`, `src/preload/`, `src/renderer/`

## Tasks
- [x] Create `src/shared/types.ts` with all cross-process interfaces
- [x] Define Pomodoro types (PomodoroStatus, SessionRecord, NextActionOption, etc.)
- [x] Define Stats types (DailyStats, WeeklyStats, ActivityData, etc.)
- [x] Define Config types (AppConfig, PomodoroConfig, TrackerConfig, etc.)
- [x] Define Tracker types (WindowActivityRecord, DailyTrackerData, etc.)
- [x] Define Uploader types (UploadRecord, CompressResult, ImageMeta, etc.)
- [x] Define Settings types (ValidationResult, WriteResult)
- [x] Add `@shared` alias to electron.vite.config.ts for all three build targets
- [x] Add paths and include entries to tsconfig.node.json and tsconfig.web.json
- [x] Migrate all ~20 files to import from `@shared/types`

## Acceptance
- [x] No type definitions remain duplicated across process boundaries
- [x] All three processes (main, preload, renderer) resolve `@shared/types` correctly
- [x] Build passes with the new path aliases
