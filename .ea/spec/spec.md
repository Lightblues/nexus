# Nexus Spec

Native macOS menu bar toolkit — Pomodoro timer, time tracker, image uploader,
command palette. Single AppKit + SwiftUI binary (post-v1.0.0 Swift rewrite of
the original Electron app).

The Swift implementation is the active codebase. The Electron-era source tree
is archived at the `legacy/electron` git tag; selected portions of its design
docs are kept under [`legacy-electron/`](legacy-electron/) for ADR cross-reference.

## Goals (achieved at v1.0.0)
- **Runtime footprint**: ~230 MB RSS / 297 MB on disk → ~30–50 MB / ~13 MB
- **One signed binary** for AX + Accessibility — no `osascript` polling, no
  cross-binary permission friction (former ADR-001)
- **Native macOS feel**: Core Animation popover, NSPanel palette, AX API, GRDB
- **Preserve user data**: `~/.ea/nexus/` layout, schema-compatible with the
  Electron build (legacy JSON stores auto-migrate on first launch)

## Non-goals
- Cross-platform support — macOS only
- Feature parity with Raycast/Alfred — palette stays scoped to Nexus actions
- Plugin/extension API

## Module Index

| File | Content |
|------|---------|
| [architecture.md](architecture.md) | App lifecycle, target layout, persistence, in-process services |
| [pomodoro.md](pomodoro.md) | Pomodoro state machine, popover layout, stats |
| [tracker.md](tracker.md) | AX-API window tracking, idle detection, GRDB storage |
| [uploader.md](uploader.md) | ImageIO compression, GitHub REST upload, drop targets |
| [palette.md](palette.md) | NSPanel palette, global hotkey, `nexus://` scheme, CommandRegistry |
| [decisions.md](decisions.md) | Swift ADRs (SADR-001 .. SADR-014). Cross-references `legacy-electron/decisions.md` for the original ADR-NNN entries |
| [migration.md](migration.md) | Electron→Swift data compatibility, rollout strategy |
| [phases.md](phases.md) | Implementation phases (0–6), exit criteria, post-mortem |
| [pitfalls.md](pitfalls.md) | Postmortem of traps hit during the migration. Read before adopting any of these patterns in a new project |
| [legacy-electron/](legacy-electron/) | Two preserved Electron-era spec files (architecture.md, decisions.md). Kept solely so SADR entries that say "see ADR-009" still resolve in working tree. Full Electron sources/spec at `legacy/electron` git tag |

## Quick reference

| Item | Electron (legacy) | Swift (current) |
|---|---|---|
| Bundle ID | `site.easonsi.nexus` | **same** (preserves Accessibility grant) |
| Min macOS | macOS 11+ (Electron 33) | macOS 13.0 (SwiftUI Charts, `MenuBarExtra`) |
| Architectures | per-arch DMG | universal binary (single DMG) |
| Data dir | `~/.ea/nexus/` | **same** |
| Config | `config.yaml` | **same** (parsed via JSON-bridge) |
| Pomodoro store | `data.json` | **same** schema, Codable + GRDB |
| Tracker store | `tracker/YYYY-MM-DD.json` | GRDB SQLite (auto-migrated) |
| Uploader store | `uploader.json` + cache | GRDB SQLite + cache |
| Logs | `logs/main.log` | **same** (`OSLog` mirror writer) |
| Distribution | electron-builder DMG, ad-hoc | `xcodebuild` archive + DMG, ad-hoc |
| Auto-update | none | none (Sparkle deferred — see SADR-006) |
| Homebrew cask | `lightblues/homebrew-tap` | **same** cask, no per-arch block |

## Coding Style (delta from project CLAUDE.md)

The CLAUDE.md style still applies (compact, type-hinted, minimal docstrings, English).
Swift specifics:
- No force-unwraps in non-test code; use `guard let` or `??`.
- Prefer `@Observable` + Swift Concurrency over Combine where possible.
- Targeting macOS 13: when an `@Observable`-only API isn't usable, fall back to
  `ObservableObject`. Note the choice in the file header.
- Keep modules under 300 lines.
