# Scripts

## `bench-memory.sh` — Memory benchmark

Snapshot footprint of running Nexus processes (Swift and/or Electron variant) so
we can track memory regressions across phases.

### Why footprint, not RSS?

`ps` shows RSS, which **includes shared library pages** (SwiftUI, AppKit,
libsystem). Those pages exist whether or not Nexus runs — they're shared with
every other app. Counting them double-charges Nexus.

`vmmap --summary <pid>` exposes `Physical footprint` — the same number Activity
Monitor's "Memory" column shows, and the official Apple metric for app cost.
For the Electron build (multi-process), we sum footprints across helpers.

### Usage

```bash
# Auto-detect any running Nexus (Swift dev build + installed Electron build):
./scripts/bench-memory.sh

# Build Release + launch + measure + kill, in one go:
./scripts/bench-memory.sh --compare

# Explicit one-off launch + measure of any .app:
./scripts/bench-memory.sh --launch /path/to/Nexus.app

# Explicit pid(s):
./scripts/bench-memory.sh 12345 67890
```

### Sample output

```
Swift Nexus (Release)
  bundle    2.6M

  swift    pid=19428  comm=Nexus
    footprint     19.3 MB  (peak 19.6 MB)
    rss           80.0 MB  (includes shared lib pages — overstates cost)
    cpu           0.0%   uptime  00:05
```

### Recorded baselines

For tracking regressions across phases, the numbers we've measured so far:

| Build | Phase | Footprint | Bundle | Notes |
|---|---|---|---|---|
| Electron 0.7 (5-proc) | shipped | ~230 MB | 297 MB | sum across main + 4 helpers |
| Swift Debug | Phase 1 | ~80 MB | 3.0 MB | Pomodoro only |
| Swift Debug + debugger | Phase 2 | 60 MB | 3.9 MB | Tracker added; lldb attached |
| Swift Release | Phase 2 | 19 MB | 2.6 MB | what users will see |
| Swift Release | Phase 3.0 | 18.6 MB | 2.6 MB | + GRDB + 32k tracker rows in SQLite |
| Swift Release | Phase 3 | 17.8 MB | 2.6 MB | + Stats + Settings (no Yams) |
| **Swift Release** | **Phase 4** | **18.8 MB** | **2.6 MB** | + Palette + global hotkey + URL scheme |

Run on the same machine (Apple Silicon M-series) to keep numbers comparable.
