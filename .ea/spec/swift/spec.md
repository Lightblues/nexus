# Nexus (Swift) Spec

**Status**: Draft. This directory specs a planned Swift rewrite of Nexus, replacing the
current Electron implementation. Companion to the top-level Electron spec — both share
the same user-facing feature set, data files, and config schema. Differences are
intentional and documented in `decisions.md` (SADR series).

## Goals
- **Drop runtime footprint**: ~230 MB RSS / 297 MB on disk → ~30–50 MB / ~10 MB.
- **Eliminate cross-binary permission friction** (ADR-001 root cause): one signed binary
  for AX + Accessibility, no `osascript` polling.
- **Native macOS feel**: Core Animation popover, panel-style palette, App Intents, Sparkle
  delta updates.
- **Preserve user data**: `~/.ea/nexus/` layout, `config.yaml` schema, archived JSON files
  all remain valid. No migration step needed for end users.

## Non-goals
- Cross-platform support (Nexus is and remains macOS-only).
- Feature parity with Raycast/Alfred — palette stays scoped to Nexus actions.
- Plugin/extension API.

## Module Index

| File | Content |
|------|---------|
| [architecture.md](architecture.md) | App lifecycle, target layout, persistence, IPC-replacement (in-process services) |
| [pomodoro.md](pomodoro.md) | Pomodoro state machine, popover layout, stats views (Swift Charts) |
| [tracker.md](tracker.md) | AX-API window tracking, idle detection, daily JSON storage |
| [uploader.md](uploader.md) | Image compression (CGImageSource), GitHub REST upload, drop targets |
| [palette.md](palette.md) | NSPanel palette, global hotkey, `nexus://` scheme, CommandRegistry |
| [decisions.md](decisions.md) | Swift-specific ADRs (SADR-001+); maps each Electron ADR to its Swift equivalent |
| [migration.md](migration.md) | Data/config compatibility, version bridging, rollout strategy |
| [phases.md](phases.md) | Implementation phases, exit criteria per phase |
| [pitfalls.md](pitfalls.md) | Postmortem of traps hit during the migration: cross-Xcode CI, packaging, runtime UI, tooling. Copy these fixes before they bite the next project. |

## Quick reference

| Item | Electron (current) | Swift (planned) |
|---|---|---|
| Bundle ID | `site.easonsi.nexus` | **same** (preserves Accessibility grant) |
| Min macOS | macOS 11+ (Electron 33) | macOS 13.0 (SwiftUI Charts, `MenuBarExtra`) |
| Architectures | arm64 + x64 | arm64 + x64 (universal binary) |
| Data dir | `~/.ea/nexus/` | **same** |
| Config | `config.yaml` | **same** (Yams) |
| Pomodoro store | `data.json` (electron-store) | **same** layout, Codable |
| Tracker store | `tracker/YYYY-MM-DD.json` | **same** |
| Uploader store | `uploader.json` + `uploader/cache/*.webp` | **same** (PNG cache; see uploader.md) |
| Logs | `logs/main.log` | **same** (`OSLog` mirror writer) |
| Distribution | electron-builder DMG, ad-hoc sign | `xcodebuild` archive + DMG, ad-hoc sign |
| Auto-update | none | Sparkle (EdDSA-signed appcast) |
| Homebrew cask | `lightblues/homebrew-tap` | **same** cask, just smaller artifact |

## Coding Style (delta from project CLAUDE.md)

The CLAUDE.md style still applies (compact, type-hinted, minimal docstrings, English).
Swift specifics:
- No force-unwraps in non-test code; use `guard let` or `??`.
- Prefer `@Observable` + Swift Concurrency over Combine where possible (macOS 14+).
- Targeting macOS 13: when an `@Observable`-only API isn't usable, fall back to
  `ObservableObject`. Mark the choice in the file header.
- Keep modules under 300 lines — the Electron side averages ~100 lines/file; Swift
  should be similar despite UI declarations being denser.
