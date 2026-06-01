# Nexus

Native macOS menu bar toolkit — Pomodoro timer, time tracker, image uploader,
command palette. Single-binary AppKit + SwiftUI app, ad-hoc signed.

See [`.ea/spec/swift/`](.ea/spec/swift/) for the full architecture and decision
log. The Electron-based predecessor is preserved at the `legacy/electron` git
tag.

## Install

```bash
brew install --cask lightblues/tap/nexus
```

Or grab the latest DMG from
[Releases](https://github.com/Lightblues/nexus/releases).

## Build from source

```bash
brew install xcodegen          # one-time
xcodegen generate              # generate Nexus.xcodeproj from project.yml
open Nexus.xcodeproj           # then ⌘R in Xcode
```

Or produce a release DMG (universal, ad-hoc signed):

```bash
./scripts/build-mac.sh         # → dist/Nexus-<version>.dmg
./scripts/install-local.sh     # build + replace /Applications/Nexus.app
```

## Why XcodeGen?

Project file is generated from `project.yml` — no merge conflicts in the
`.xcodeproj` binary plist, no manual file-add dance. Drop a `.swift` file
in the right folder, re-run `xcodegen generate`.

## Directory layout

Mirrors [`.ea/spec/swift/architecture.md`](.ea/spec/swift/architecture.md):

```
Nexus/
├── App/                # @main, AppDelegate, AppEnvironment
├── Core/               # Paths, Config, DataStore, Logger, Database, ...
├── Features/
│   ├── Pomodoro/       # Timer service + popover + sheets
│   ├── Tracker/        # Active-window polling + stats
│   ├── Uploader/       # GitHub image uploader + jsdelivr CDN
│   ├── Palette/        # ⌘K command palette
│   └── ...
└── Resources/          # Info.plist, Assets, default-config.json
```

## Data

User data lives at `~/.ea/nexus/` (config, SQLite databases, log mirror).
Schema-compatible with the Electron build's data files — first launch
auto-migrates legacy JSON stores.
