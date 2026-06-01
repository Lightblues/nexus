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
- **Data**: `~/.ea/nexus/`
- **Spec**: `.ea/spec/` (active spec — `spec.md` is the index). `.ea/spec/legacy-electron/` holds two preserved Electron-era files (architecture, decisions) for SADR cross-reference. Full Electron sources at the `legacy/electron` git tag.

## Coding Style
- Compact and type-hinted
- Minimal docstrings (only for public methods with non-obvious logic)
- Simple and clear, avoid over-engineering
- Language: English

## Swift Environment
- Project generator: **XcodeGen** (`project.yml` → `Nexus.xcodeproj`, gitignored)
- Min macOS: 13.0 (SwiftUI Charts, `MenuBarExtra` cohort)
- Package manager: **SwiftPM** (deps declared in `project.yml`: GRDB)
- Swift mode: 5.9, strict concurrency `minimal` (Xcode 15 CI compat)

## Git
- NEVER use `git commit` directly — code must be reviewed first
- Only use `gh` CLI tools after user approval
