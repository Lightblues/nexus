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

4. **Cross-actor calls in nonisolated SwiftUI View methods** (the v1.2.0 release blocker):

   ```swift
   // BAD — Xcode 16 warns, Xcode 15 errors
   private struct SettingsTrampoline: View {
       let appDelegate: AppDelegate
       var body: some View {
           Color.clear.onAppear { route() }
       }
       private func route() {
           appDelegate.environment.mainWindow.show(route: .settings) // ❌ MainActor-isolated method called from nonisolated context
       }
   }

   // GOOD
   @MainActor
   private func route() {
       appDelegate.environment.mainWindow.show(route: .settings)
   }
   ```

   SwiftUI `View` instance methods are nonisolated by default. They're invoked
   from main-isolated callbacks (`onAppear`, `onChange`), so at runtime the
   call is fine — but Swift's static checker doesn't know that. Xcode 16
   tolerates the implicit hop; Xcode 15 demands an explicit `@MainActor` on
   the method (or `await`/`Task { @MainActor in ... }` at the call site).
   This caused the v1.2.0 release to fail in CI while passing locally;
   v1.2.1 fixed it by annotating `route()`.

   See `NexusApp.swift:36`.

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

### 3.4 Menu-bar popover dragging MainWindow forward

**Symptom**: User in vscode (focused on A monitor). Click Nexus menu-bar icon
on B monitor → popover appears, but Nexus's MainWindow on A monitor is
yanked to the foreground, stealing vscode's focus.

**Root cause**: `togglePopover()` called `NSApp.activate(ignoringOtherApps: true)`
right after `popover.show(...)`, "so SwiftUI text fields in the editor sheet
can take key focus". But `NSApp.activate` is a **process-level** operation —
it raises *all* of Nexus's windows to front, not just the popover. Combined
with `MainWindowController` setting activation policy to `.regular` while
MainWindow is open (for cmd-tab to behave normally), every popover open
becomes "treat Nexus like a regular foreground app", dragging the visible
MainWindow forward.

**Fix**: Decouple activation from popover visibility. The popover itself
doesn't need app activation — buttons (Start/Pause/Finish/Exit) work fine
without it. Only activate when actually needed (the edit-session sheet's
TextFields). Move the `NSApp.activate` call from `togglePopover()` into the
edit button's action:

```swift
// AppDelegate.togglePopover — drop the activate call entirely
pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
installClickOutsideMonitor()

// PomodoroPopoverView edit-button action — activate just-in-time
Button(action: {
    NSApp.activate(ignoringOtherApps: true)
    showEditor = true
}) { ... }
```

**Lesson**: `NSApp.activate(ignoringOtherApps: true)` is process-level
nuclear option. For menubar apps where popover ≠ "user wants the whole app
foregrounded", call activate only at the precise moment a key window needs
focus, and never preventively.

### 3.5 Palette keyboard nav vs. mouse hover deadlock

**Symptom**: Open palette, hover mouse over row 2, press ↓ — selection
appears to move to row 3 then **snaps back to row 2 immediately**. Keyboard
navigation effectively dead anywhere the mouse is parked.

**Root cause**: Naïve `.onHover { hovering in if hovering { selection = idx } }`
on every row. When ↓ moves selection from row 2 to row 3, both rows
re-render (isSelected changed). SwiftUI's `.onHover` re-fires `hovering=true`
during the re-render for whichever row the cursor is sitting on (it doesn't
distinguish "cursor entered area" from "cursor stayed in area through
re-render"). That fires `selection = 2` and undoes the keystroke.

**Fix**: Track which input device drove the last selection change.
Hover-to-select only fires while in `.mouse` mode. Real cursor *motion*
(via `NSTrackingArea` `.mouseMoved`, NOT SwiftUI's enter/exit-only `onHover`)
flips back to `.mouse` mode:

```swift
@State private var lastInput: InputKind = .mouse
private enum InputKind { case keyboard, mouse }

// onHover guard
.onHover { hovering in
    guard hovering, lastInput == .mouse else { return }
    selection = idx
}
// ↑↓ + query change set lastInput = .keyboard
// MouseMotionDetector (NSViewRepresentable wrapping NSTrackingArea) sets
// lastInput = .mouse on real motion events.
```

This is what Spotlight/Raycast/Alfred all do — the pattern is the standard
"cursor was where the keyboard left off; respect that until the user
actually moves the mouse."

**Bonus**: Don't double-key your `ForEach` rows. We had:

```swift
ForEach(Array(matches.enumerated()), id: \.element.id) { idx, cmd in
    CommandRow(cmd: cmd, isSelected: idx == selection)
        .id(idx)         // ❌ second identity, fights with ForEach's
}
```

`.id(idx)` overrides ForEach's identity with an int that *doesn't* change
when matches list mutates. SwiftUI then reuses cells positionally and shows
stale views. Use ForEach's identity (the element's stable id) and drop
`.id()`. If `ScrollViewReader.scrollTo(...)` was using `idx`, switch it to
`matches[idx].id`.

### 3.6 SwiftUI Settings scene races AppDelegate.bootstrap

**Symptom**: v1.2.1 launched fine on the developer machine but crashed on
`/Applications/Nexus.app/Contents/MacOS/Nexus` when installed via `brew
upgrade`. The crash signature in stderr:

```
Nexus/MainWindowController.swift:46: Fatal error: MainWindowController: environment not attached
```

— from `makeWindow()`'s `guard let env = environment else { fatalError(...) }`.

**Root cause**: SwiftUI's `Settings { ... }` scene declared in `NexusApp.body`
is mounted **as part of the very first SwiftUI commit pass**, which runs
during `NSApp` startup. The `SettingsTrampoline` view's `.onAppear` calls
`appDelegate.environment.mainWindow.show(route: .settings)` *before* the
`Task { @MainActor in await environment.bootstrap() }` dispatched from
`applicationDidFinishLaunching` has executed its synchronous prefix.

`AppEnvironment.bootstrap()` had `mainWindow.attach(environment: self)`
buried after several `await` hops (catalog migration, repository refresh,
etc.). On a cold cache the SwiftUI dispatch wins; the trampoline calls
`show()` → `makeWindow()` → `environment` is still nil → fatalError.

The race had been latent since v1.0.0; v1.2.0 introduced
`SettingsTrampoline.onAppear → mainWindow.show()` and exposed it. The
trampoline is the *only* code path that calls `mainWindow.show()` before
user interaction.

**Fix — two layers**:

1. **Hoist sync wiring above any `await`**:
   ```swift
   func bootstrap() async {
       // FIRST — before any await — wire up singletons that
       // hold AppEnvironment back-references.
       mainWindow.attach(environment: self)
       palette.attach(environment: self)

       config.bootstrap()
       notifier.setup()
       await CatalogMigration.runIfNeeded(db: database)
       // ...
   }
   ```
   These attach calls don't need `await`; the only reason they were at the
   bottom was alphabetic accident.

2. **Belt-and-suspenders `show()` race guard**:
   ```swift
   func show() {
       guard environment != nil else {
           DispatchQueue.main.async { [weak self] in self?.show() }
           return
       }
       // ...existing code
   }
   ```
   If a future code path beats the bootstrap synchronously again, we
   defer one runloop tick instead of fatalError-ing.

**General rule**: anything dispatched from `App.body` Scenes (SwiftUI's
sync mount path) can run before `applicationDidFinishLaunching`'s `Task`
gets its first `await` hop. Singletons reachable from those Scenes must
be wired up either in `AppEnvironment.init` (before `bootstrap()` runs)
or as the synchronous prefix of `bootstrap()`. Anything that requires
`await` ordering needs its own race guard at the call site.

**Why developer machine masked the crash**: incremental dev builds had
warm caches and a slightly different Task-scheduler timing than a
freshly-mounted brew DMG on first launch. The race surfaced on cold-cache
launches, not consistently on dev cycles. Conclusion: "I tested locally"
is not signal for launch-time races; cold-cache install-from-DMG is.

---

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

> **v1.2.0 note**: config now lives at
> `~/Library/Application Support/site.easonsi.nexus/config.json`, and
> `migrate-data-v1.2.0.sh` `mv`s the file (preserving the symlink) into the
> new location. The mackup `.cfg` entry that previously named
> `.ea/nexus/config.yaml` no longer resolves; re-establishing sync is a manual
> step. The symlink-resolution fix above remains in place — same code path,
> just acting on a file under `Library/...` now.

### 4.3 Bundle ID continuity is sacred

**Symptom (avoided)**: We considered renaming `site.easonsi.nexus` to something
shorter. Would have triggered re-prompt for Accessibility, Notifications, Apple
Events on every existing user — and broken Mackup's bundle-ID-keyed prefs.

**Decision**: bundle ID is **frozen**. Any user-facing rebrand (display name,
icon, copy) is fine; the underlying CFBundleIdentifier never changes. See
SADR-001.

### 4.4 "Same bundle id" silently masks freshly-installed builds

**Symptom (cost us ~2 hours)**: Run `install-local.sh`, see "✓ Installed",
open the app, see broken UI that *doesn't match the source code on disk*.
Edit + reinstall, still broken in the same way. Conclusion: "code bug,
investigate further" — actually the new build was never running.

**Root cause**: macOS allows only one running instance per bundle id. If an
older build is already running (typically the **Xcode-launched Debug build**
at `~/Library/Developer/Xcode/DerivedData/.../Nexus.app`), a freshly-launched
copy of `/Applications/Nexus.app` sees its bundle slot taken and **silently
exits**. There's no error, no log, no menubar visual change — the user's
"after install" UI is still driven by the stale Xcode-launched binary. And
because Xcode's lldb is holding the Debug process, even `kill -9` on it from
a script does nothing; it's stopped (`SX` state) but not gone.

**Fix**: `install-local.sh` now kills both `/Applications/Nexus.app/...`
*and* `DerivedData/Nexus-.*/Build/Products/.*/Nexus.app/...`, then warns
explicitly if anything is still alive after the wait — pointing the user at
"press ⌘. in Xcode" rather than scratching their head.

```bash
pkill -f "/Applications/Nexus.app/Contents/MacOS/Nexus" || true
pkill -f "DerivedData/Nexus-.*/Build/Products/.*/Nexus.app/Contents/MacOS/Nexus" || true
# wait a beat, then:
if pgrep -f "DerivedData/Nexus-.*Nexus.app/Contents/MacOS/Nexus" >/dev/null; then
  echo "⚠️  Xcode is holding a Debug build under lldb. ⌘. in Xcode, then re-run."
fi
```

**Lesson** (this is the meta-lesson we cared about): when the user reports
"I clicked, behavior is wrong", **before** debugging the code — verify
*which binary they're actually looking at*. `ps aux | grep Nexus.app` and
the binary path it's running is a 2-second sanity check that prevents
arbitrarily long debugging on a build that doesn't exist anymore.

---

## 5. Three meta-lessons

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

3. **When a UI bug "doesn't match the code", verify the running binary first.**
   The expensive trap of this migration was spending ~2 hours debugging a
   palette UI bug that turned out to be a stale Xcode-launched Debug build
   masking the freshly-installed Release build (§4.4). The right debug
   sequence — applied any time a user says "the change didn't take" — is:

   1. **`ps aux | grep Nexus.app | grep -v grep`** — what process(es) are
      actually running, and from which path? `/Applications/...` ≠
      `DerivedData/...` ≠ a debug attach holding `.SX` state.
   2. **Check binary mtime + log timestamps** — does the running binary's
      file mtime match a recent build? Does the log show a `launched` entry
      *after* the install?
   3. **Read the log for evidence**, not assumptions — does the bootstrap
      sequence match what the source code says it should do? (We added
      `registry: appended <id>` log lines and instantly proved the registry
      was correct, redirecting attention to the SwiftUI render layer.)
   4. **Only then** start reading code or guessing at logic.

   This sequence is cheap (seconds) and routinely saves hours. The
   `install-local.sh` script now contains the protections + warnings that
   make Step 1 reliable.

These three together prevented ~80% of the back-and-forth on this migration.
