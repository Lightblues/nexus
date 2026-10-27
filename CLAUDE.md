# nexus

macOS menu bar toolkit — Pomodoro timer, image uploader, time tracker, command palette.

Native AppKit + SwiftUI single-binary app. The Electron implementation is
archived at the `legacy/electron` git tag.

## Quick Reference
- **Install**: `brew install --cask lightblues/tap/nexus`
- **Dev**: `xcodegen generate && open Nexus.xcodeproj` → ⌘R
- **Build DMG**: `./scripts/build-mac.sh` → `dist/Nexus-<version>.dmg`
- **Local install**: `./scripts/install-local.sh` (build + replace `/Applications/Nexus.app`)
- **Release**: bump `CFBundleShortVersionString` in `project.yml`, tag `nexus-vX.Y.Z`, push → CI builds DMG, creates GitHub Release, bumps Homebrew cask
- **Bundle ID**: `site.easonsi.nexus` (frozen — Mackup + AX permission continuity)
- **Data**: `~/Library/Application Support/site.easonsi.nexus/` (config + db); `~/Library/Caches/...` (thumbnails); `~/Library/Logs/...` (main.log). v1.2.0 migration: run `./scripts/migrate-data-v1.2.0.sh` once before first launch on the new layout. See SADR-015.
- **Spec**: `.ea/docs/` (active spec — `spec.md` is the index). `.ea/docs/legacy-electron/` holds two preserved Electron-era files (architecture, decisions) for SADR cross-reference. Full Electron sources at the `legacy/electron` git tag.

## Coding Style
- Compact and type-hinted
- Minimal docstrings (only for public methods with non-obvious logic)
- Simple and clear, avoid over-engineering
- Language: English

## Swift Environment
- Project generator: **XcodeGen** (`project.yml` → `Nexus.xcodeproj`, gitignored)
- Min macOS: 13.0 (SwiftUI Charts, `MenuBarExtra` cohort)
- Package manager: **SwiftPM** (deps declared in `project.yml`: GRDB 7, local `Packages/NexusSync`)
- Toolchain: CI builds on `macos-15` with Xcode 16.4; GRDB 7 needs Xcode 16+ (7.9+ need 16.3+). See SADR-017.
- Swift mode: 5.9, strict concurrency `minimal`
- `Packages/NexusSync` (sync logic) builds and tests on Linux; command in `.ea/docs/sync.md` → Swift client

## Git
- Commit finished work yourself once its checks pass (build and tests as relevant), one commit per logical change in the repository's commit style, then push `main`. No separate review step is needed.
- Forge issues: `.ea/issues/` is synced by the forge server and is not committed.
- Only use `gh` CLI tools after user approval
