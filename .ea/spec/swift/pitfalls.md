# Pitfalls & Lessons Learned

Postmortem from the Electron → Swift migration. Each entry captures the **symptom**,
**root cause**, and **fix that landed**, so the next macOS app project can copy the
fix instead of rediscovering the trap.

Companion to `decisions.md` (which records *what* we chose). This file records
*what bit us when we chose it*.

---

## 1. Cross-Xcode-version compatibility (the biggest CI bleed)

Local Xcode versions move faster than the macOS GitHub runner. Three concrete
traps fall out of that mismatch.

### 1.1 `objectVersion = 77` rejected by CI Xcode 15

**Symptom**: CI fails with `error: Project file format is too new (objectVersion = 77)`.

**Root cause**: My local Xcode 26 (macOS Tahoe beta) writes pbxproj at format
77; CI's Xcode 15 only understands ≤ 56.

**Fix**: `scripts/build-mac.sh` patches the freshly-generated project after
`xcodegen` and before `xcodebuild`:

```bash
PBXPROJ="$PROJECT_DIR/Nexus.xcodeproj/project.pbxproj"
CURRENT=$(awk '/objectVersion = / {gsub(";",""); print $3; exit}' "$PBXPROJ")
if [[ -n "$CURRENT" && "$CURRENT" -gt 56 ]]; then
  sed -i.bak 's/objectVersion = [0-9]*;/objectVersion = 56;/' "$PBXPROJ"
  rm -f "$PBXPROJ.bak"
fi
```

Pin to 56 (Xcode 15.0+ baseline). Don't pin to whatever the local Xcode emits.

### 1.2 Swift 6 strict concurrency errors that don't fire locally

**Symptom**: 5 distinct Swift compile errors in CI (Xcode 15) that don't
reproduce on Xcode 26 — all `Capture of '…' with non-sendable type …` or
`Mutation of captured var …`.

**Root cause**: Strict concurrency lints are tier-gated by Swift version; newer
toolchains have already absorbed some of them as warnings, older treat them as
errors.

**Fix — three patterns** (apply preventively, don't wait for CI):

1. **`var x` mutated inside `db.write { }`**: the `@Sendable` closure can't
   capture a mutable. Hoist the accumulation outside, return a value:

   ```swift
   // BAD
   var imported = 0
   try db.write { db in
       imported += try insertRows(db)   // ❌ capture of var
   }

   // GOOD
   let imported = try db.write { db in
       try insertRows(db)
   }
   ```

2. **`[weak self]` then `Task { self?.x }`** in a `Timer` callback: the implicit
   capture path through Task isn't recognised. Bridge through a sendable local:

   ```swift
   let timer = Timer(...) { [weak self] _ in
       let weakSelf = self                           // bridge
       Task { @MainActor in weakSelf?.tick() }
   }
   ```
   See `PomodoroService.swift:124–128`, `TrackerService.swift:74-86, 93-97`.

3. **Belt-and-suspenders**: in `project.yml`,

   ```yaml
   settings:
     base:
       SWIFT_STRICT_CONCURRENCY: minimal
   ```
   Catches the long tail of actor-isolation lints we don't want on Xcode 15 CI.

### 1.3 General rule

> Local "it builds" is not signal. The **only** signal is the CI runner's Xcode
> version. If you must use a beta Xcode locally, write the build script
> defensively (sed-patch + STRICT_CONCURRENCY=minimal) from day one — don't wait
> for the first red CI run to discover the gap.

---

## 2. Packaging & distribution

### 2.1 `hdiutil create: No such file or directory`

**Symptom**: CI build fails at the DMG step. Local works.

**Root cause**: I removed `mkdir -p` lines during a refactor. CI runs in a
clean checkout where neither `dist/` nor `build/archive/` exists; local works
because I had stale dirs.

**Fix**: always run

```bash
rm -rf "$BUILD_DIR/archive" "$BUILD_DIR/export"
mkdir -p "$DIST_DIR" "$BUILD_DIR/archive" "$BUILD_DIR/export"
```

before any tool that *reads* a directory. Don't trust the previous run.

### 2.2 Cask SHA bump regex didn't match split-arch format

**Symptom**: CI step "bump cask sha" runs without error, but the cask file is
unchanged.

**Root cause**: The cask was originally written with `arch arm:` / `arch intel:`
blocks (two SHAs). The CI bump regex only matches a single `sha256 "…"`.
Universal binary → single SHA → cask should be in single-SHA form.

**Fix (do once)**: pre-refactor the cask to single-SHA layout *before* CI tries
to bump it:

```ruby
cask "nexus" do
  version "1.0.0"
  sha256 "0" * 64           # placeholder, CI rewrites
  url "https://…/Nexus-#{version}.dmg"
end
```

Lesson: when you change the artifact shape (per-arch → universal), update the
*release tooling that touches the cask* in the same PR — not in the PR after.

### 2.3 `install-local.sh` couldn't parse `hdiutil attach` output

**Symptom**: Script can't find the mount point; exits before copying the .app.

**Root cause**: `hdiutil attach` output is tab-separated, but volume names with
spaces (e.g. `/Volumes/Nexus 1.0.0`) confuse naive `awk '{print $3}'` parsing.

**Fix**: use the structured output:

```bash
MOUNT=$(hdiutil attach -plist -nobrowse "$DMG" | \
        python3 -c 'import sys, plistlib; \
                    p = plistlib.loads(sys.stdin.buffer.read()); \
                    print([e for e in p["system-entities"] \
                          if e.get("mount-point")][0]["mount-point"])')
```

### 2.4 `xcodebuild` failed: "tool 'xcodebuild' requires Xcode"

**Symptom**: Build script bombs immediately.

**Root cause**: `xcode-select -p` was pointing at `/Library/Developer/CommandLineTools`
(Xcode CLT only), not Xcode.app. CLT doesn't ship `xcodebuild`.

**Fix**: one-time on dev machines + CI:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

CI runners default to Xcode.app already; only matters if you switched recently.

---

## 3. Runtime UI bugs

### 3.1 Pomodoro draft metadata didn't persist

**Symptom**: project / tags edited in popover are gone after relaunch.

**Root cause**: race in `init`:

```swift
init(...) {
    Task { self.draftMetadata = store.data.meta.lastSession }  // ❌ runs before store.load()
}
```

The Task fires immediately (with `data` still at default empty value), then
`store.load()` finishes — but draftMetadata was already snapshotted from the
empty pre-load state.

**Fix**: drop the implicit-load pattern. Make hydration explicit, called *after*
`store.load()`:

```swift
func hydrate() {
    if let persisted = PomodoroRepository.loadPersistedDraft() {
        draftMetadata = persisted
    } else {
        draftMetadata = repository.lastSession
    }
    sessionsSinceLongBreak = repository.sessionsSinceLongBreak
}
```

`PomodoroService.swift:34-41`. Lifecycle:
1. construct service (no async fetch)
2. `await repository.bootstrap()`
3. **then** `service.hydrate()`
4. attach to UI

### 3.2 NSPopover doesn't close on outside click

**Symptom**: Clicking the desktop while popover is open does nothing — popover
stays.

**Root cause**: NSPopover only closes on its own `transient` behavior or when
the status item is clicked. Outside clicks aren't a default close trigger.

**Fix**: install a global event monitor while the popover is shown:

```swift
self.globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .rightMouseDown]
) { [weak self] _ in self?.close() }
```

Tear down in `popoverWillClose`. Don't forget the symmetric local monitor if
you also want clicks *on* the popover bar to close (we didn't — popover stays
open during interactions, so global-only is correct).

### 3.3 Palette (NSPanel) doesn't close on outside click

**Symptom**: Same as 3.2 but for the command palette.

**Root cause**: NSPanel without `hidesOnDeactivate` keeps showing. We *want* it
to dismiss on outside click but *not* on internal clicks.

**Fix**: dual monitors, with a window check on the local side:

```swift
self.globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
    [weak self] _ in self?.dismiss()
}
self.localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
    [weak self] event in
    if event.window === self?.panel { return event }   // keep palette interactions
    self?.dismiss()
    return nil
}
```

The local monitor's `event.window === self.panel` check is the linchpin —
without it, *every* click inside the palette (including selecting an item)
fires the dismiss.

---

## 4. Tooling-layer paper cuts

### 4.1 Edit tool duplicated content

**Symptom**: Several `Edit` calls (NumberStepper, RouteRequest, build-mac.sh
section) silently produced *appended* instead of replaced text.

**Root cause**: When `old_string` matches more than once and `replace_all` isn't
set, the tool errors. But when there's an *adjacent* match — e.g. "the same
struct definition appearing twice in a row" — the result is one valid replace
+ one apparent duplication.

**Fix**: after any non-trivial Edit, `Read` the file region back. For known
trouble spots, prefer `awk`/`sed` for line-level deletes followed by a single
clean `Write`.

### 4.2 mackup symlink writes overwrite the symlink

**Symptom**: Edits to `config.json` got mysteriously reverted; mackup-tracked
files lost their backup.

**Root cause**: `~/.ea/nexus/config.json` is a symlink to
`~/Documents/Mackup/.ea/nexus/config.json`. `Data.write(to:)` on the symlink
path replaces the *symlink* with a regular file, breaking the mackup chain.

**Fix**: resolve symlinks before writing:

```swift
let target = (try? FileManager.default
    .destinationOfSymbolicLink(atPath: url.path))
    .map { URL(fileURLWithPath: $0) } ?? url
try data.write(to: target, options: .atomic)
```

Apply uniformly to *every* config/data writer that might land on a tracked
file. We did this in `Config.swift` and `CatalogMigration.swift`.

### 4.3 Bundle ID continuity is sacred

**Symptom (avoided)**: We considered renaming `site.easonsi.nexus` to something
shorter. Would have triggered re-prompt for Accessibility, Notifications, Apple
Events on every existing user — and broken Mackup's bundle-ID-keyed prefs.

**Decision**: bundle ID is **frozen**. Any user-facing rebrand (display name,
icon, copy) is fine; the underlying CFBundleIdentifier never changes. See
SADR-001.

---

## 5. Two meta-lessons

1. **Local Xcode ≠ CI Xcode. Build defensively from day one.** The
   `objectVersion` patch and `STRICT_CONCURRENCY=minimal` should be the *first*
   things in any new project's build script, not added in panic after the
   first red CI. Cost is zero; benefit is a working CI on day one.

2. **`@Sendable` closures + `[weak self]` + `Task` is a landmine field.**
   Default to:
   - mutate state *outside* the closure (return value from inside)
   - bridge `weak self` through a `let weakSelf = self` local before any nested
     Task
   - turn down strict concurrency to `minimal` until you've explicitly opted
     into Swift 6 mode
   - assume the *older* compiler in CI is the gating one — write to its rules

These two together prevented ~80% of the back-and-forth on this migration.
