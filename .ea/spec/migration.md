# Migration: Electron → Swift

Two distinct migration moments are documented here:

1. **Electron → Swift (v1.0.0)**: First Swift build read all of the Electron
   app's data files in place at `~/.ea/nexus/` and rewrote / imported them.
   Compatibility matrix and one-shot logic below.
2. **`~/.ea/nexus/` → standard macOS layout (v1.2.0)**: After the rewrite was
   stable, all data moved to the system-furnished paths under `~/Library/...`.
   See "v1.2.0 path migration" at the bottom and SADR-015.

The user's `~/.ea/nexus/` directory must keep working across the v1.0.0 cutover.
This file specs what data the Swift build must read on first launch and what (if
anything) it rewrites.

## Compatibility matrix

| File | Electron writer | Swift reader | Action on first Swift launch |
|---|---|---|---|
| `~/.ea/nexus/config.yaml` | `js-yaml` | Yams | Read as-is. Re-emit only if user edits in-app (preserves comments via Yams `Node` API where possible). |
| `~/.ea/nexus/data.json` | `electron-store` | Codable | **Migrate**: unwrap electron-store wrapper, rewrite as bare struct. See below. |
| `~/.ea/nexus/archive/pomodoro-{YYYY}.json` | bare JSON array | Codable | Read as-is. No migration needed. |
| `~/.ea/nexus/tracker/{YYYY-MM-DD}.json` | bare JSON struct | Codable | Read as-is. Schema unchanged (`version: 1`). |
| `~/.ea/nexus/uploader.json` | bare JSON | Codable | Read as-is. |
| `~/.ea/nexus/uploader/cache/{id}.webp` | sharp | ImageIO | Read as-is. New thumbnails written with same `.webp` extension via ImageIO. |
| `~/.ea/nexus/logs/main.log` | electron-log | OSLog file mirror | Append new lines; do not truncate. Rotate at 5 MB matches Electron behavior. |

## `data.json` shape migration

**Electron-store form** (current):
```json
{
  "sessions": [...],
  "meta": { "projects": [...], "tags": [...], "lastSession": {...} }
}
```

The current Electron build already stores at the top level (no electron-store wrapper
key visible — confirmed by inspection of `DataManager.ts` defaults). If a future
electron-store version added wrapping, the Swift loader would need to detect and
unwrap. Spec the migration defensively:

```swift
struct PomodoroData: Codable {
    var sessions: [SessionRecord]
    var meta: PomodoroMeta
    var schemaVersion: Int = 1   // new field; absent in Electron files → defaults to 1
}

extension PomodoroStore {
    func loadWithMigration() throws -> PomodoroData {
        let data = try Data(contentsOf: dataURL)
        // Try direct decode first
        if let direct = try? JSONDecoder.iso8601.decode(PomodoroData.self, from: data) {
            return direct
        }
        // Fallback: unwrap potential electron-store wrapper
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let inner = json?["__internal__"] as? [String: Any] ?? json {
            let inner = try JSONSerialization.data(withJSONObject: inner)
            return try JSONDecoder.iso8601.decode(PomodoroData.self, from: inner)
        }
        throw MigrationError.unknownShape
    }
}
```

The first save after migration writes the Swift-canonical shape with explicit
`schemaVersion`.

## ID compatibility

- Electron uses `uuid` v4 strings. Swift `UUID` round-trips to the same canonical
  string. Codable `UUID` decodes lowercase hex with hyphens — matches Electron output.
- electron-store stores `Date` as ISO 8601 strings; Swift uses `JSONDecoder.iso8601`
  with a custom strategy that accepts both `Z` and `+00:00` suffix. Verified against
  Electron sample files in the test fixtures.

## Bundle ID continuity

Both builds use `site.easonsi.nexus`. macOS treats them as the same app for:
- Accessibility permission grant
- Apple Events grants
- Notification settings
- LaunchServices "default app for nexus:// scheme" registration

No re-grant needed unless the codesign Team ID changes. Both builds use ad-hoc
signing (no Team ID), so the system treats them as continuous.

## Homebrew cask cutover

```ruby
# Casks/nexus.rb — pre-cutover (Electron, per-arch)
cask "nexus" do
  arch arm: "arm64", intel: "x64"
  version "0.7.0"
  sha256 arm: "...", intel: "..."
  url "https://.../Nexus-#{version}-#{arch}.dmg"
end

# Post-cutover (Swift, universal)
cask "nexus" do
  version "1.0.0"
  sha256 "..."
  url "https://.../Nexus-#{version}.dmg"
  # postflight quarantine strip continues unchanged
end
```

The version jump signals the user-facing rewrite. `brew upgrade --cask nexus`
replaces the bundle in-place.

## Rollout plan

1. **Beta tap**: ship Swift builds to `lightblues/homebrew-tap/Casks/nexus@beta.rb`
   for ~2 weeks. Flag known regressions vs the v0.7 Electron build.
2. **Side-by-side run**: bundle ID stays the same, so beta and stable can't both
   run — accept this. Beta testers explicitly opt out of stable.
3. **Cutover**: bump main cask to Swift v1.0.0. Keep an `Casks/nexus@electron.rb`
   pointing at the last v0.7.x DMG for users who hit issues, until v1.1 ships.
4. **End of life**: archive the Electron source under a `legacy/electron` git
   branch + tag for reproducibility.

## Roll-back

If a user needs to revert:
```bash
brew install --cask lightblues/tap/nexus@electron
```
The Swift build won't have rewritten any data files yet on first launch (it migrates
in-memory and writes only on the first user action that mutates state). If the user
opens MainWindow and clicks "Edit session", that triggers a write. To support a
clean roll-back path, the Swift build keeps a one-time backup `data.json.electron-bak`
on first migration write.

## Tests required before cutover

| Test | Coverage |
|---|---|
| Decode current Electron `data.json` fixture into `PomodoroData` | shape compatibility |
| Decode 5+ archived `pomodoro-{YYYY}.json` fixtures | archive compatibility |
| Decode current `tracker/{YYYY-MM-DD}.json` fixture | schema v1 parity |
| Round-trip: Electron writes → Swift reads → Swift writes → Swift reads | idempotency |
| Bundle ID continuity: install Electron, grant AX, replace with Swift, observe AX still active | permission survival |
| Hotkey grab on launch with Raycast also installed | conflict-free coexistence |
| Drop image on tray icon | drop receiver works |
| `nexus://command/pomodoro.start` from Shortcuts.app | URL scheme registered |

---

## v1.2.0 path migration: `~/.ea/nexus/` → standard macOS layout

See SADR-015 for rationale. v1.2.0 stops reading or writing under
`~/.ea/nexus/`; data lives at:

| Kind | New path |
|---|---|
| Config + DB | `~/Library/Application Support/site.easonsi.nexus/` |
| Cache | `~/Library/Caches/site.easonsi.nexus/` |
| Logs | `~/Library/Logs/site.easonsi.nexus/` |

### One-shot script (no in-app migration code)

`scripts/migrate-data-v1.2.0.sh` is the canonical migration. Run **before**
launching v1.2.0 for the first time:

```bash
./scripts/migrate-data-v1.2.0.sh
```

What it does:
1. Quits any running Nexus (both `/Applications/Nexus.app` and Xcode debug builds).
2. Detects no-op cases: already-migrated, or fresh install — exits cleanly.
3. Creates the three new directories under `~/Library/`.
4. `mv` user-critical files (`config.json`, `nexus.db`, `nexus.db-wal`,
   `nexus.db-shm`) into Application Support. `mv` preserves symlinks so any
   existing mackup chain on `config.json` survives.
5. Archives the old root: `~/.ea/nexus/` → `~/.ea/nexus.pre-v1.2.0-bak-<timestamp>/`.
   Caches (uploader thumbnails) and logs are not migrated — thumbnails rebuild
   on the next upload, OSLog has its own retention.
6. Cleans Electron-era residue: `~/Library/Application Support/nexus/`
   (33 MB Chromium leftovers) and `~/Library/Logs/nexus/` get renamed to
   `*.electron-bak-<timestamp>`.
7. Idempotent — re-runs harmlessly.

### Why the script and not in-app code

Previous Electron→Swift migration code lived in `LegacyMigration.swift`.
That code is **deleted in v1.2.0**: a one-time path move belongs in a script,
not the app's hot path. Keeping migration logic out of the app:
- Keeps app launch deterministic (no I/O before window appears)
- No risk of a half-migrated state if the app crashes during the move
- Failure surfaces in the user's terminal, not in main.log
- Migration can be `--dry-run`-ed and re-tried independently

### Rollback

If v1.2.0 misbehaves, the path back is symmetric:

```bash
# Stop Nexus, then
mv ~/.ea/nexus.pre-v1.2.0-bak-<timestamp> ~/.ea/nexus
mv ~/Library/Application\ Support/site.easonsi.nexus ~/Library/Application\ Support/site.easonsi.nexus.v1.2.0-bak
# Reinstall the previous .dmg from GitHub Releases (Nexus-1.1.0.dmg)
```
