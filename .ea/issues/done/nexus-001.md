---
schema_version: 1
id: nexus-001
title: Adopt standard macOS data layout (SADR-015)
status: done
priority: medium
estimate: L
labels: [refactor, data-layout, macos]
isolation: local
delivery: none
---

## Objective
Move Nexus's on-disk state off the inherited `~/.ea/nexus/` directory and onto the
standard macOS locations keyed by bundle id `site.easonsi.nexus`, and move the
one-time path migration out of the app and into an idempotent shell script.

## Context
- `.ea/spec/decisions.md` — holds SADR-015, the accepted decision record that fixes the four target locations and the reasoning for splitting user-critical data from regenerable data.
- `.ea/spec/architecture.md` — its "Data Layout" table and "Persistence Layer" section are the normative description of what lives where.
- `.ea/spec/migration.md` — its "v1.2.0 path migration" section specifies the one-shot script contract, the no-op cases, and the rollback path.
- `Nexus/Core/Paths.swift` — the single source of truth for every location the app reads or writes; the whole change pivots on this file.
- `Nexus/Core/Config.swift` — `ConfigService` seeds, loads, hot-reloads, and saves `config.json` through `Paths.configFile`.
- `Nexus/Core/Database/Database.swift` — opens the shared GRDB `DatabaseQueue` at `Paths.dbFile` with `journal_mode = WAL`.
- `Nexus/Core/Logger.swift` — owns the file sink that appends to and rotates `Paths.mainLog`.
- `Nexus/App/AppEnvironment.swift` — the bootstrap sequence; this is where the deleted in-app legacy importer used to be invoked.
- `Nexus/App/AppDelegate.swift` — calls the launch banner at `didFinishLaunching`, which is what makes each session greppable in the log.
- `scripts/migrate-data-v1.2.0.sh` — the one-shot, out-of-band migration that replaces the deleted in-app importer.
- `CLAUDE.md` — its "Data" quick-reference line has to name the new locations, since that line is how a contributor learns where the app's state is.
- `.ea/spec/spec.md` — its quick-reference table carries the data-dir / config / logs rows that would otherwise contradict the new layout.

## Tasks
- [x] Rewrite `Nexus/Core/Paths.swift` to resolve the support, caches, and logs roots via `FileManager.default.urls(for:in:)` and append `bundleID`, dropping the `~/.ea/nexus` root and the legacy paths only the deleted importer used
- [x] Repoint `ConfigService` and `Database` at the new Application Support directory (`config.json`, `nexus.db` + WAL sidecars)
- [x] Move the log file sink to `~/Library/Logs/site.easonsi.nexus/main.log`, render the source location as `<basename>:<line>`, and raise retention from 1 to 4 rotated generations
- [x] Add `Log.writeLaunchBanner()` and call it from `AppDelegate.didFinishLaunching`
- [x] Delete `Nexus/Core/Database/LegacyMigration.swift` and remove its call from `AppEnvironment.bootstrap()`
- [x] Add `scripts/migrate-data-v1.2.0.sh`: early exits for the already-migrated and fresh-install cases, symlink-preserving `mv` of the user-critical files, archive the old root, clear Electron-era residue
- [x] Update `.ea/spec/decisions.md` (SADR-015), `architecture.md`, `migration.md`, `spec.md`, `pitfalls.md`, and `CLAUDE.md` to describe the new layout

## Acceptance
- [x] `Nexus/Core/Paths.swift` builds every path from `FileManager.default.urls(for:in:)` plus `bundleID`; no Swift code path is assembled from a literal `~/Library/...` or `~/.ea/nexus` string
- [x] `Paths` exposes 8 `static` members — the `bundleID` constant and 7 URLs (`supportDir`, `cachesDir`, `logsDir`, `configFile`, `dbFile`, `uploaderCacheDir`, `mainLog`) — down from the pre-change set that also carried `dataFile`, `uploaderFile`, `archiveDir`, `trackerDir`, `archiveFile(year:)`, `trackerFile(date:)`, `legacyWindowStateFile`, and `cleanupLegacyFiles()`
- [x] `Nexus/Core/Database/LegacyMigration.swift` is absent from the tree and no source file, script, or document references `LegacyMigration`, `legacyWindowStateFile`, or `cleanupLegacyFiles`
- [x] `scripts/migrate-data-v1.2.0.sh` guards both no-op cases — an already-populated `nexus.db` in Application Support with no legacy root, and a missing `~/.ea/nexus` — so a second run moves nothing
- [x] `CLAUDE.md` and `.ea/spec/spec.md` both name Application Support / Caches / Logs keyed by bundle id rather than `~/.ea/nexus/`
- [x] The change shipped: tag `nexus-v1.2.0` exists and the working tree is on a later release

## Boundaries
- Always: resolve on-disk locations through `FileManager` plus `bundleID` in `Paths.swift`, so the paths follow the system rather than being written out as literal `~/Library/...` strings
- Never: reintroduce in-app migration code for a one-time path move — the move belongs in `scripts/migrate-data-v1.2.0.sh`, where it can be dry-run, re-tried, and rolled back independently of app launch
- Ask: before changing `bundleID` — it is frozen because Mackup setups and the Accessibility permission grant are keyed to it

## Outcome
- Status: done
- Date: 2026-06-01
- Summary: Rewrote `Paths.swift` around `FileManager.urls(for:in:)` + `bundleID`, so `config.json` and `nexus.db` live in `~/Library/Application Support/site.easonsi.nexus/`, uploader thumbnails in `~/Library/Caches/site.easonsi.nexus/`, and `main.log` in `~/Library/Logs/site.easonsi.nexus/`. Deleted `LegacyMigration.swift` (the pre-v1.0 Electron-JSON importer) and moved the path move itself into the new idempotent `scripts/migrate-data-v1.2.0.sh`, which `mv`s the user-critical files, archives the old `~/.ea/nexus/` root, and clears Electron-era residue. Also shortened the log source location to `<basename>:<line>`, raised retention to 4 rotated generations, and added a per-launch banner.
- Files changed:
  - `.ea/spec/architecture.md` — new "Data Layout" table, rewritten Logging section
  - `.ea/spec/decisions.md` — SADR-015 added
  - `.ea/spec/migration.md` — "v1.2.0 path migration" section appended
  - `.ea/spec/pitfalls.md` — mackup-symlink note updated for the new config path
  - `.ea/spec/spec.md` — data-dir / config / logs rows in the quick reference
  - `CLAUDE.md` — "Data" line
  - `Nexus/App/AppDelegate.swift` — launch banner call
  - `Nexus/App/AppEnvironment.swift` — dropped the legacy-importer call
  - `Nexus/Core/Config.swift` — doc comment pointing at the new config path
  - `Nexus/Core/Database/Database.swift` — doc comment pointing at the new db path
  - `Nexus/Core/Database/LegacyMigration.swift` — deleted
  - `Nexus/Core/Logger.swift` — source-location format, 4-generation retention, `writeLaunchBanner()`
  - `Nexus/Core/Paths.swift` — rewritten around `FileManager` + `bundleID`
  - `Nexus/Features/MainWindow/MainWindowController.swift` — doc comment pointing at the new layout
  - `scripts/migrate-data-v1.2.0.sh` — added
  - `.ea/inst/index.md` — also edited by this change; that file has since been removed from the tree, so it is not part of the current layout
- Verification: The change is commit `9c6b32e` ("refactor(data): adopt standard macOS data layout (SADR-015)"), merged as PR #14 and released as tag `nexus-v1.2.0` (`cafca0d`); the tree now carries v1.2.3. Static checks against the current tree: `grep -rn "urls(for:" Nexus/` returns only the three `FileManager` root lookups in `Paths.swift`; `grep -rn 'Library/Application Support\|\.ea/nexus\|homeDirectoryForCurrentUser' Nexus/ --include=*.swift` matches doc comments only, never executable code; `grep -rn 'LegacyMigration\|legacyWindowStateFile\|cleanupLegacyFiles' Nexus/ scripts/ CLAUDE.md` returns nothing; `git tag -l nexus-v1.2.0` returns the tag. The migration script was **not** executed during this check — this machine still has a populated `~/.ea/nexus/`, and running it would move the user's live data. Its two no-op branches were confirmed by reading the script instead. No test suite covers this change: `project.yml` declares no test target, so verification is static evidence plus the released commit, not a test run.
- Notes: Two consequences are deliberate and documented in SADR-015. First, mackup integration breaks — a `.mackup.cfg` entry naming `.ea/nexus/config.yaml` no longer resolves, and re-establishing sync is an explicit user step. Second, `LegacyMigration.swift` is deleted rather than deprecated: the pre-v1.0 import already ran for the migrated user, so carrying it forward served no purpose. The migration must run before the first v1.2.0 launch; `ConfigService` writes `config.json` through `destinationOfSymbolicLink` so a re-created mackup symlink in the new location still resolves. This record was reconstructed on 2026-10-08 from the git history, after the work landed and after forge adoption — the `Date` above is the completion date of the original change, not the date this file was written.
