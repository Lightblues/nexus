# Nexus

Native macOS menu bar toolkit — Pomodoro timer, time tracker, image uploader,
command palette. Single-binary AppKit + SwiftUI app, self-signed (no Apple Developer ID).

See [`.ea/docs/`](.ea/docs/README.md) for the full architecture and decision
log. The Electron-based predecessor is preserved at the `legacy/electron` git
tag.

## Install

```bash
brew install --cask lightblues/tap/nexus
```

Or grab the latest DMG from
[Releases](https://github.com/Lightblues/nexus/releases).

Beta (a build of every push to `main`, updated within ten minutes; data is kept):

```bash
curl -fsSL https://raw.githubusercontent.com/Lightblues/nexus/main/scripts/beta.sh | bash -s install
# back to stable: ~/Library/Application\ Support/site.easonsi.nexus/beta.sh uninstall
```

## Build from source

```bash
brew install xcodegen          # one-time
xcodegen generate              # generate Nexus.xcodeproj from project.yml
open Nexus.xcodeproj           # then ⌘R in Xcode
```

Or produce a release DMG (universal; ad-hoc signed locally, CI signs with the project's identity):

```bash
./scripts/build-mac.sh         # → dist/Nexus-<version>.dmg
./scripts/install-local.sh     # build + replace /Applications/Nexus.app
```

## Why XcodeGen?

Project file is generated from `project.yml` — no merge conflicts in the
`.xcodeproj` binary plist, no manual file-add dance. Drop a `.swift` file
in the right folder, re-run `xcodegen generate`.

## Directory layout

Mirrors [`.ea/docs/architecture.md`](.ea/docs/architecture.md):

```
Nexus/
├── App/                # @main, AppDelegate, AppEnvironment
├── Core/               # Paths, Config (settings in nexus.db), Logger, Database, ...
├── Features/
│   ├── Pomodoro/       # Timer service + popover + sheets
│   ├── Tracker/        # Active-window polling + stats
│   ├── Uploader/       # GitHub image uploader + jsdelivr CDN
│   ├── Palette/        # ⌘K command palette
│   └── ...
└── Resources/          # Info.plist, Assets
```

## Data

User data lives in the standard macOS places (SADR-015): the SQLite database, which
also holds the settings, in `~/Library/Application Support/site.easonsi.nexus/`,
thumbnails in `~/Library/Caches/site.easonsi.nexus/`, the log in
`~/Library/Logs/site.easonsi.nexus/`. There is no config file: change settings in the
app or with `nexus config set`. Versions before v1.2.0 used `~/.ea/nexus/`; that data
is not read any more.

Sync (off by default): Settings → Sync, turn it on and paste the server key;
settings, pomodoro data and tracker records then converge across Macs through
`https://nexus.easonsi.site`. See [`.ea/docs/sync.md`](.ea/docs/sync.md).
