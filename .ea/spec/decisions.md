# Swift-side Architecture Decisions (SADRs)

These ADRs are specific to the Swift rewrite. For each Electron ADR with a direct
Swift counterpart, the mapping is recorded at the bottom under "Inherited / mapped".

---

## SADR-001: Keep bundle ID `site.easonsi.nexus`
**Status**: Accepted

**Context**: macOS records Accessibility, Apple Events, and Notification grants by
bundle ID. The Electron build's v0.5.0 release already paid the user-facing cost of
renaming `com.ea.nexus → site.easonsi.nexus` (changelog notes a forced re-grant).

**Decision**: The Swift binary keeps `site.easonsi.nexus`. Existing users' AX grant
applies automatically the first time the new build runs. No re-prompt unless macOS
detects a code-signing identity change (ad-hoc → ad-hoc is the same TeamID-less
bucket, so it should pass through silently — verify in beta).

**Consequence**: Smooth upgrade. If the user installed via Homebrew cask, the cask
upgrade replaces the bundle in-place and the AX grant survives.

---

## SADR-002: AppKit `NSStatusItem` + `NSPopover`, not SwiftUI `MenuBarExtra`
**Status**: Accepted

**Context**: SwiftUI 13+ ships `MenuBarExtra` which appears to obsolete the AppKit
status item dance. But: (a) the uploader feature drops images on the icon — needs
the underlying button view to register drag types; (b) the pomodoro feature writes
to `attributedTitle` 1Hz — `MenuBarExtra` re-renders the whole label; (c) custom
popover sizing/animation is awkward in `MenuBarExtra`.

**Decision**: Use `NSStatusItem` directly. SwiftUI views are embedded via
`NSHostingController` inside `NSPopover`. The status button's view is replaced with
a custom `NSView` subclass that hosts the icon and accepts drag types.

**Rejected alternatives**:
- `MenuBarExtra(.window)` — drag receiver isn't pluggable; would need private API
  to attach drag types to the menu bar item.
- Hybrid (MenuBarExtra for icon, custom NSPopover for content) — two ownership
  models in conflict.

**Consequence**: ~50 lines of AppKit boilerplate at app start. In return, full
control over the status item.

---

## SADR-003: `@Observable` over `ObservableObject`
**Status**: Accepted (with macOS 13 fallback noted)

**Context**: Swift 5.9 / macOS 14 introduced the `@Observable` macro, which removes
`@Published` boilerplate and produces fine-grained dependency tracking. Available on
the macOS-13 deployment target via the Observation backport in newer toolchains.

**Decision**: Default to `@Observable` for all services. If a specific call site can't
use it (e.g. legacy SwiftUI bridge), fall back to `ObservableObject` and document the
reason at the top of the file.

**Consequence**: Less boilerplate, fewer over-renders. Slight risk if the
Observation backport surfaces compatibility issues — bake into the beta phase.

---

## SADR-004: One target, no XPC services, no helper bundles
**Status**: Accepted

**Context**: The Electron build ships 4 helper bundles (Renderer, GPU, Plugin,
Network) — each a separate process driven by Chromium's sandbox model. Translating
that to Swift's XPC services would reproduce the multi-process overhead we're
trying to escape (~80 MB across helpers in the Electron build).

**Decision**: Single binary. AX polling, image compression, network upload, UI all
run in the same process. Use Swift Concurrency (`Task.detached`, actors) for
concurrency without process boundaries.

**Rejected alternatives**:
- XPC service for image compression — would isolate sharp-equivalent crashes from
  the main app, but ImageIO is mature and crash-resistant; not worth the IPC
  overhead and bundle complexity.
- XPC service for the AX poller — same reasoning. AX call failures are recoverable.

**Consequence**: Simpler bundle structure. Single Accessibility prompt. No nested
codesign chain (sidesteps the Electron-build ADR-011 trap entirely).

---

## SADR-005: Drop `electron-store` shape, use per-feature codable JSON
**Status**: Accepted

**Context**: electron-store wraps user data in a top-level container with a
`__internal__` schema-version key. The Swift port could mimic that, but the only
purpose was electron-store's own bookkeeping.

**Decision**: Each feature owns a typed `Codable` struct serialized as the root JSON
object. `data.json` becomes `PomodoroData`; `uploader.json` becomes `UploaderData`;
tracker keeps per-day files. A small migration step on first launch reads the
electron-store wrapped form and rewrites it as the bare struct (see `migration.md`).

**Consequence**: One-way migration on first Swift launch. Files become more readable
(no extra wrapping). Future schema changes use a `version: Int` field at the struct
root.

---

## SADR-006: Sparkle for auto-update
**Status**: Deferred (revisit at v2)

**Context**: The Electron build has no auto-update — users get new versions only via
`brew upgrade --cask nexus`. That's fine for the `brew` users but loses the chance
to nudge non-Homebrew installers.

**Original decision**: Integrate Sparkle 2 with EdDSA-signed appcast at
`https://github.com/Lightblues/nexus/releases/latest/download/appcast.xml`. Auto-check
weekly, prompt user before downloading. The Homebrew tap continues to work as the
primary distribution; Sparkle is a fallback for direct DMG users and a way to surface
release notes inside the app.

**Why deferred at v1.x**: Single-developer project, small user base, brew + manual
DMG cover both audience cohorts. The marginal value of Sparkle (one-click in-app
update for non-brew users) doesn't outweigh ~5 hours of integration + EdDSA key
management surface area at this scale. Revisit when (a) user count grows enough that
"go to GitHub Releases" feels like a cliff, or (b) we need to ship a security-relevant
fix and brew cadence isn't fast enough.

**Consequence if/when adopted**: Two install paths (cask + Sparkle) must be kept in
sync via the release pipeline. Adds ~3 MB to the bundle (Sparkle.framework). The
EdDSA private key becomes an attack vector — must live in GitHub Secrets, never in
the repo.

---

## SADR-007: Yams for YAML, not custom parser
**Status**: Accepted

**Context**: Three real choices for YAML parsing in Swift: Yams (LibYAML wrapper —
mature), a hand-rolled parser, or shelling out to a YAML CLI. The config schema is
small but has nested structures, lists, and quoted-string edge cases.

**Decision**: Use [Yams](https://github.com/jpsim/Yams) via SwiftPM. It's the de facto
choice (used by SwiftLint, Vapor), MIT-licensed, single-dep.

**Rejected alternatives**:
- Hand-rolled — too much YAML edge-case surface area.
- JSON-only config — would break compatibility with existing `~/.ea/nexus/config.yaml`.

**Consequence**: One transitive dep. `Package.resolved` pins the version.

---

## SADR-008: Carbon `RegisterEventHotKey` for global hotkey
**Status**: Accepted

**Context**: macOS has two paths for global hotkeys: Carbon HotKey API and
`NSEvent.addGlobalMonitorForEvents`. The latter requires monitoring **every** key
event in the system — wasteful and triggers false-positive Accessibility prompts.
Carbon HotKey installs a kernel-level filter and only fires for the configured combo.

**Decision**: Wrap Carbon's `RegisterEventHotKey` in `Core/HotKey.swift`. It's
deprecated in name but actively maintained (used by Magnet, Rectangle, etc.).

**Rejected alternatives**:
- `NSEvent.addGlobalMonitor*` — no Accessibility benefit, monitors all keys, adds
  overhead.
- `MASShortcut` library — wraps Carbon but adds a dep + UI components we don't need.

**Consequence**: A 60-line `HotKey.swift` wrapper. No prompt for "Input Monitoring"
permission (which `addGlobalMonitor` would trigger).

---

## SADR-009: Use ImageIO + (optional) `libwebp` for compression, not link `sharp` / libvips
**Status**: Accepted

**Context**: `sharp` (libvips) is the gold standard for fast image processing in
Node. macOS ships ImageIO, which covers JPEG / PNG / WebP / HEIC encode + decode at
performance comparable to libvips for typical web image sizes (≤ 4K).

**Decision**: Compression goes through ImageIO. PNG palette optimization parity
with sharp's libimagequant is deferred — v1 ships with vanilla PNG. If the
compression ratio gap proves user-visible, add an optional `libimagequant` binary
in v2.

**Consequence**: No native binary linking, no x86/arm64 fat-lib management. Slightly
larger PNGs in worst case (~10-20% vs sharp). JPEG/WebP are at parity.

---

## SADR-010: AX-API + lean Apple Events (browser URL only), drop AppleScript
**Status**: Accepted

**Context**: Electron ADR-001 chose AppleScript-via-`osascript` to avoid bundling a
separate `get-windows` binary (which required its own AX permission). Now we're
already a single signed binary, so the original constraint disappears.

**Decision**: Window title + bundle ID via AX (`AXUIElementCopyAttributeValue`).
**Browser URL** still requires Apple Events because no public AX attribute exposes
browser tab URLs — so we keep a single compiled `NSAppleScript` per browser, called
only when the front app is in `enrichApps`.

**Consequence**: Per-poll cost drops from ~50 ms (osascript fork) to ~1 ms (AX) for
non-browsers, and ~5 ms (compiled NSAppleScript reuse) for browsers. Same
Accessibility grant. Apple Events permission is requested lazily on first browser
URL fetch.

---

## SADR-011: NSPanel `nonactivatingPanel`, port of Electron ADR-013
**Status**: Accepted

**Context**: ADR-013 fixed a bug where summoning the palette dragged MainWindow to
the global foreground because Electron's `BrowserWindow.show()` calls
`[NSApp activate]`. The Electron fix used `type: 'panel'` (Electron PR #41750).

**Decision**: Same model in Swift — `NSPanel` subclass with `.nonactivatingPanel`
style mask, `becomesKeyOnlyIfNeeded = true`, `hidesOnDeactivate = true`. The dismiss
path never calls `NSApp.hide(nil)`, preserving MainWindow visibility.

**Consequence**: Identical UX to the Electron build's post-ADR-013 state. The latent
bug from the pre-fix Electron palette is impossible to reintroduce because the
underlying primitive (NSPanel) is what gives us the property.

---

## SADR-012: Universal binary, drop per-arch DMG split
**Status**: Accepted

**Context**: Electron build ships separate `arm64` and `x64` DMGs (Cask uses
`arch arm:` block). A universal Swift binary is a small added size (~30%) that
simplifies distribution.

**Decision**: `ARCHS = arm64 x86_64`, single `Nexus.dmg`. Cask drops the `arch`
block. Single sha256 to track.

**Consequence**: One artifact in the release. The CI matrix shrinks from
`{arm64, x64}` to a single `macos-latest` job. Bundle size up from ~10 MB to ~13 MB
(both arches), still 95%+ smaller than Electron.

---

## SADR-013: Drop Dashboard view (Electron `Dashboard.tsx`)
**Status**: Accepted

**Context**: The Electron build has a `Dashboard.tsx` (39 lines, 4 emoji
cards: 🍅 Pomodoro / 🖼️ Uploader / 📝 Notes / ⚙️ Settings). It serves as the
default landing page of `MainWindow` because the hash router needs *something*
to show on `#/`. Functionally it's a feature launcher, not a dashboard — there
is no aggregate today-view data on it.

**Decision**: Don't port. The Swift main window already has three superior
entry surfaces:
- **Sidebar**: always-visible list (Stats / Tracker / Uploader / Settings),
  zero clicks to switch
- **Menu bar popover**: Pomodoro is one click away from anywhere in the OS
- **Command palette (⌘K)**: directly invokes any registered action without a
  visit to MainWindow

Each of these dominates the Electron Dashboard on at least one axis (latency,
ubiquity, action depth), and together they fully cover its job.

**Consequence**: First-launch route is `.stats` (already a data-rich view), not
a launcher screen. If a future "Today" overview is genuinely wanted, it's a new
sub-view of `StatsView` or a new `MainRoute.today` case — explicitly *not* a
revival of the Electron Dashboard's launcher pattern.

---

## SADR-014: Repo hoist + Electron archival
**Status**: Accepted

**Context**: During the Electron→Swift migration the Swift sources lived under
`nexus-swift/` so the two stacks could coexist. Once Electron parity reached
v1.0.0 and `src/` was no longer being touched, the `nexus-swift/` prefix had no
remaining purpose: every script, CI workflow, README link, and IDE breadcrumb
paid an extra path segment for nothing. macOS apps in the wild (Sparkle, GRDB,
Rectangle, Stats, Ice) keep the project at repo root; the subdirectory was a
migration scaffold, not a convention.

**Decision**: After v1.1.0 ship, two-commit cleanup on a single branch:
1. **Archive Electron** — `git rm -rf src/ electron-builder.yml electron.vite.config.ts package.json pnpm-lock.yaml tsconfig*.json resources/ build/entitlements.mac.plist scripts/test-*.mjs scripts/install-release.sh`. Tag the prior tip as `legacy/electron` (annotated, points to commit `c73e496` = `release: nexus v0.7.0`) so Electron sources are reachable via `git checkout legacy/electron`.
2. **Hoist** — `git mv nexus-swift/* .` for `Nexus/`, `scripts/`, `project.yml`, `README.md`. Merge `nexus-swift/.gitignore` into root `.gitignore`. Drop the `REPO_ROOT="$PROJECT_DIR/.."` hop from `scripts/generate-app-icon.sh`. Strip `working-directory: nexus-swift` from `.github/workflows/build.yml` and rewrite the artifact glob `nexus-swift/dist/Nexus-*.dmg` → `dist/Nexus-*.dmg`.

The two-commit split gives git's rename detector a clean signal: commit 2 shows
~75 100% renames instead of "delete A + add B" pairs, which makes review and
future blame clean.

**Consequence**: Repo root mirrors what an external contributor expects from a
macOS Swift project — `Nexus/`, `project.yml`, `scripts/`, `README.md`,
`.github/`. The `.ea/spec/` (Electron-era top-level) stays in place as a
historical spec; `.ea/spec/swift/` remains the active spec. The
`legacy/electron` tag is the single recovery handle for Electron code; nothing
else points to it.

---

## Inherited / mapped from Electron ADRs

The Electron-era ADR full text lives at
[`legacy-electron/decisions.md`](legacy-electron/decisions.md). The table below
maps each one to its Swift fate.

| Electron ADR | Status in Swift | Swift counterpart |
|---|---|---|
| ADR-001 (osascript over get-windows) | **Reverted** | Native AX API now that single-binary lifts the dual-permission constraint (SADR-010) |
| ADR-002 (Shared types) | **N/A** | One process, no IPC, types live with the service that owns them |
| ADR-003 (IPC channel constants) | **N/A** | No IPC layer; service method signatures are the contract |
| ADR-004 (Auto-archiving) | **Preserved** | `PomodoroStore.runArchiveSweep()` at launch, identical 90-day cutoff |
| ADR-005 (IPC listener cleanup) | **N/A** | `@Observable` handles teardown; no manual listener bookkeeping |
| ADR-006 (Hash routing) | **Preserved as enum** | `enum MainRoute { case stats, tracker, settings }` |
| ADR-007 (Unified edit modal) | **Preserved** | Single SwiftUI sheet for idle + running |
| ADR-008 (pnpm enforcement) | **N/A** | SwiftPM only, no JS toolchain |
| ADR-009 (CommandRegistry as unified surface) | **Preserved** | `Core/CommandRegistry.swift`, same shape |
| ADR-010 (Hotkey default `Cmd+Shift+Space`) | **Preserved** | Same default; `HotKey.swift` reads `cfg.hotkey.palette` |
| ADR-011 (Ad-hoc codesign via electron-builder) | **Replaced** | Single binary; `xcodebuild` ad-hoc signing handles it correctly. The "deep / inside-out" pitfall doesn't apply |
| ADR-012 (Homebrew tap) | **Preserved** | Same tap, simpler cask (no per-arch block per SADR-012) |
| ADR-013 (Palette as panel) | **Preserved** | NSPanel `nonactivatingPanel` (SADR-011) |

---

## See also

[`pitfalls.md`](pitfalls.md) — postmortem of traps the *implementations* of these
decisions hit. Each pitfall entry is keyed to the decision (or omission) that
caused it; if you adopt one of these SADRs in a new project, read the
corresponding pitfall first.
