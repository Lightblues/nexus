# Tracker (Swift)

Replaces the Electron tracker (`../tracker.md`). The big win here vs Electron is
**dropping AppleScript** for native AX APIs — single Accessibility grant, ~50× lower
per-poll cost.

## Tracking pipeline

```
Timer (every cfg.pollInterval s)
  ↓
Permissions.isAXTrusted? ──no──→ disable polling, surface banner
  ↓ yes
HIDIdleTime > cfg.idleThreshold? ──yes──→ skip
  ↓ no
ActiveAppProbe.fetch()  →  (bundleId, appName, windowTitle)
  ↓
ContextEnricher.enrich(probe)  →  ActivityContext
  ↓
TrackerService.merge(probe, context)
  if same app+file+url as current head → extend endTime
  else → finalize current, start new
  ↓
buffer in memory; flush every 5 min or on app shutdown
  ↓
~/.ea/nexus/tracker/YYYY-MM-DD.json
```

## Active App Probe (`Tracker/ActiveAppProbe.swift`)

Replaces the AppleScript poll with two AX calls:

```swift
struct ActiveProbe {
    let bundleId: String
    let appName: String
    let windowTitle: String
    let url: String?      // browser-only, set by enricher
}

enum ActiveAppProbe {
    static func fetch() -> ActiveProbe? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var focusedWindow: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString,
                                      &focusedWindow)
        guard let window = focusedWindow else { return nil }
        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(window as! AXUIElement,
                                      kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""
        return ActiveProbe(
            bundleId: app.bundleIdentifier ?? "",
            appName: app.localizedName ?? "",
            windowTitle: title,
            url: nil
        )
    }
}
```

**Performance**: AX calls return in well under 1 ms vs ~50 ms for `osascript` in
ADR-001. At 5-second poll interval the difference is negligible per-poll, but it
matters for short-interval debugging and battery (no `osascript` process spawn).

## Idle Detection (`Tracker/IdleDetector.swift`)

The Electron version used `powerMonitor.getSystemIdleTime()`. Swift equivalent uses
the IOKit HID service:

```swift
enum IdleDetector {
    static func systemIdleSeconds() -> TimeInterval {
        var iter: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"), &iter)
        defer { IOObjectRelease(iter) }
        let entry = IOIteratorNext(iter)
        defer { IOObjectRelease(entry) }
        var props: Unmanaged<CFMutableDictionary>?
        IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0)
        let dict = props?.takeRetainedValue() as? [String: Any] ?? [:]
        let ns = dict["HIDIdleTime"] as? UInt64 ?? 0
        return TimeInterval(ns) / 1_000_000_000  // ns → s
    }
}
```

Skip the merge step if `systemIdleSeconds() >= cfg.idleThreshold`.

## Context Enrichment (`Tracker/ContextEnricher.swift`)

Per-app strategies, picked by bundle id:

| Bundle ID | Strategy |
|---|---|
| `com.microsoft.VSCode`, `com.todesktop.230313mzl4w4u92` (Cursor) | Title parser: `"file — project"` → `(file, project)` |
| `com.google.Chrome`, `com.apple.Safari`, `company.thebrowser.Browser` | URL via Apple Events (`tell application "Chrome" to get URL of active tab of front window`) |
| (default) | bundleId + window title only |

For browsers we **must** keep an Apple Events path (no native API exposes browser
tab URL). But unlike Electron's full `osascript` invocation per poll, we use a single
persistent `NSAppleScript` instance compiled once and executed per call — ~5 ms vs
~50 ms.

If `AEDeterminePermissionToAutomateTarget` returns denied, fall back to title-only
(no URL/domain enrichment for that app). Surface in Settings → Tracker.

## Merge Algorithm (unchanged from Electron)

Same comparison key (`app + context.file`), same finalize-on-change semantics. Code
moves into `TrackerService.merge(_:)`. Tests use the same fixtures.

## Storage (`TrackerStore.swift`)

`tracker/YYYY-MM-DD.json` — schema in `../tracker.md` is preserved exactly:

```swift
struct DailyTrackerData: Codable {
    let date: String           // "YYYY-MM-DD"
    let version: Int           // = 1
    var records: [WindowActivityRecord]
    var meta: TrackerDayMeta
}
```

In-memory buffer flushed every 5 min or on `applicationWillTerminate`. Each flush:
1. Serialize current day's records.
2. Write to `tracker/YYYY-MM-DD.json.tmp`.
3. `rename` over the existing file (atomic).
4. Update `meta.totalActiveTime` and `meta.appSummary` aggregates.

## UI (`Features/Tracker/Views/TrackerView.swift`)

Lives in MainWindow's `tracker` route. Layout from `../tracker.md`:

```
┌─────────────────────────────────────────┐
│ Time Tracker             [date picker]  │
├─────────────────────────────────────────┤
│ Timeline (00:00 ────────────── 24:00)   │
├──────────────────┬──────────────────────┤
│  Donut chart     │  APP rank list       │
│  (top 5 + other) │  (expandable)        │
└──────────────────┴──────────────────────┘
```

- **TrackerTimeline** — `Canvas`-drawn 24h horizontal bar. Per-app deterministic color
  via `appName.hashColor()`. Hover shows time range + app + file in an overlay.
- **AppUsageDonut** — Swift Charts `SectorMark`. Center label = total time.
- **AppRankList** — `List` with disclosure rows; expanding shows top contexts (file/url
  breakdown) sorted by duration.

## Permissions

- AX: requested via `Permissions.requestAccessibility()` on first
  `TrackerService.start()`.
- Apple Events (for browser URL): requested lazily on first browser title needing
  URL. If denied, log + degrade. Both cases surface in Settings → Tracker as a
  banner with an "Open System Settings" deep link.

## Commands (initial)

| ID | Action |
|---|---|
| `tracker.toggle` | Enable/disable polling |
| `tracker.openToday` | Open MainWindow → tracker route, today selected |
| `tracker.flushNow` | Force a buffer flush (debug) |

## Config (unchanged)

```yaml
tracker:
  enabled: true
  pollInterval: 5
  idleThreshold: 120
  recordTitle: false
  enrichApps: ['Code', 'Google Chrome']
```

`enrichApps` continues to whitelist which app names get URL/title enrichment to
avoid prompting Apple Events permission for apps the user doesn't want tracked
deeply.
