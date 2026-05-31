# Nexus (Swift)

Native Swift rewrite of Nexus. Replaces the Electron implementation in `../src/`
with a single-binary AppKit + SwiftUI app. See `../.ea/spec/swift/` for the full
spec.

## Status

Phase 0–1 (scaffold + Core + Pomodoro MVP) — work in progress.

## Build

```bash
brew install xcodegen          # one-time
xcodegen generate              # produces Nexus.xcodeproj from project.yml
open Nexus.xcodeproj           # then ⌘R in Xcode
# or:
xcodebuild -scheme Nexus -configuration Debug build
```

## Why XcodeGen?

Project file is generated from `project.yml`. No merge conflicts in `.xcodeproj`
binary plist, no manual file-add dance — drop a `.swift` file into the right
folder and run `xcodegen generate` again.

## Directory layout

Mirrors `.ea/spec/swift/architecture.md`:

```
Nexus/
├── App/                # @main, AppDelegate, AppEnvironment
├── Core/               # Paths, Config, DataStore, Logger, Permissions, ...
├── Features/
│   └── Pomodoro/       # Service, Store, Views
└── Resources/          # Info.plist, Assets, default-config.yaml
```

## Data compatibility

Reads existing `~/.ea/nexus/` files written by the Electron build. See
`../.ea/spec/swift/migration.md`.
