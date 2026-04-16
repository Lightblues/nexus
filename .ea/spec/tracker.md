# Auto-Tracker (Time Tracking)

Automatic time tracking based on active window monitoring. Independent from Pomodoro, stored separately.

## Features
- Background window tracking using **AppleScript** via `osascript`
- Browser URL extraction (Chrome, Safari, Arc)
- Idle detection via `powerMonitor.getSystemIdleTime()`
- Per-day JSON file storage
- Activity merging (consecutive same app+file → single record)
- App-specific context enrichment (VSCode project/file, Browser URL/domain)
- Does NOT prevent macOS sleep

## Data Structure
```typescript
interface ActivityContext {
  project?: string   // e.g., VSCode project name
  file?: string      // filename or page title
  url?: string       // browser URL
  domain?: string    // extracted hostname
  rawTitle?: string  // original window title (AI fallback)
}

interface WindowActivityRecord {
  startTime: string  // ISO 8601
  endTime: string
  duration: number   // seconds
  app: string
  bundleId?: string
  context?: ActivityContext
}

interface DailyTrackerData {
  date: string       // "YYYY-MM-DD"
  version: 1
  records: WindowActivityRecord[]
  meta: {
    totalActiveTime: number
    appSummary: Record<string, number>
  }
}
```

## Storage
- Path: `~/.ea/nexus/tracker/YYYY-MM-DD.json`
- Buffer in memory, flush every 5 minutes or on shutdown
- Meta summary updated on each flush

## Context Enrichment
- **VSCode/Cursor**: Parse title `"filename — project-name"` → `file`, `project`
- **Browser**: AppleScript to get URL → extract `domain`, title as `file`
- BundleId-based matching for Electron apps (VSCode, Cursor show as "Electron")

## Merge Algorithm
- Poll every `pollInterval` seconds
- Skip if idle >= `idleThreshold`
- Compare by `app` + `context.file`
- Same: update `endTime`; Different: finalize + create new

## Config (`config.yaml`)
```yaml
tracker:
  enabled: true
  pollInterval: 5
  idleThreshold: 120
  recordTitle: false
  enrichApps: ['Code', 'Google Chrome']
```

## UI (MainWindow → Time Tracker tab)
```
┌─────────────────────────────────────────┐
│ Time Tracker                 [date picker]│
├─────────────────────────────────────────┤
│ Timeline (00:00 ────────────── 24:00)   │
├──────────────────┬──────────────────────┤
│  Donut chart     │  APP rank list       │
│  (top 5 + other) │  (expandable context)│
└──────────────────┴──────────────────────┘
```

Components:
- **TrackerTimeline**: 24h horizontal bar, app-colored segments, tooltip
- **AppUsageChart**: Donut chart, center = total time
- **AppRankList**: Sorted by duration, expandable context breakdown
