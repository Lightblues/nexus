# Tracker

Records which app (and, for editors and browsers, which project, file, or site) is in
front, as rows in `tracker_records` in nexus.db. The server turns the rows into
categorized day summaries ([sync.md](sync.md) → Day summaries).

## Pipeline (`TrackerService.tick`, every `tracker.pollInterval` s)

```
tracker.enabled? ──no──→ stopped
Accessibility granted? ──no──→ waitingForPermission: system prompt once per launch,
  ↓ yes                        a notification after 10 min, recheck every 2 s
HID idle ≥ tracker.idleThreshold? ──yes──→ idle, nothing recorded
  ↓ no
ActiveAppProbe.fetch()  →  app name, bundle id, focused window title (AX)
lock screen / screen saver in front? ──yes──→ idle, nothing recorded
  ↓
ContextEnricher.enrich  →  project, file, url, domain (apps in tracker.enrichApps)
  ↓
same app + file as the last row, and the last row ended ≤ 3 polls (min 15 s) ago?
  yes → extend its end_time      no → insert a new row
```

The gap rule is what keeps idle time, sleep, and the lock screen out: after any of
them, the next poll starts a new row instead of stretching the old one across the gap.

## Probe and enrichment

- `ActiveAppProbe`: `NSWorkspace.frontmostApplication` plus the focused window's
  `kAXTitleAttribute`. VS Code and Cursor report themselves as Electron, so their
  names come from a bundle-id map (`Code`, `Code - Insiders`, `Cursor`).
- `ContextEnricher` runs only for apps named in `tracker.enrichApps` (default: Code,
  Code - Insiders, Cursor, Google Chrome, Google Chrome Beta, Safari, Arc; the pre-v1.3.2
  default `["Code", "Google Chrome"]` is upgraded to it on load).
  - Editors: `parseEditorTitle` reads VS Code's "file — folder — profile" title; the
    folder is the project (a " (Workspace)" suffix dropped, an SSH remote kept).
  - Browsers: the active tab's URL through a compiled `NSAppleScript` per browser (one
    Apple Events grant per browser; denial disables it for that browser until relaunch).
  - Every enriched row keeps the raw title in `context_raw_title`.
- `tracker.recordTitle` decides whether `title` is stored for apps that are not enriched.

## Storage

`tracker_records`: `start_time`, `end_time`, `duration` (seconds), `app`, `bundle_id`,
`title`, `context_project`, `context_file`, `context_url`, `context_domain`,
`context_raw_title`, `uid` (sync id). Sync pushes rows on its 5-minute timer.
`TrackerRepository` keeps the last row this Mac wrote (by uid) for extension across
launches.

## UI (`Features/Tracker/Views/`)

The main window's Tracker route for one day: a 24 h timeline, a donut of the top apps,
and a ranked app list that expands into files and sites.

## Commands

| ID | Action |
|---|---|
| `tracker.toggle` | Enable or disable polling |
| `tracker.openToday` | Open the Tracker route on today |

## Config

`tracker.enabled` (true), `pollInterval` (5 s), `idleThreshold` (120 s),
`recordTitle` (false), `enrichApps` (above).
