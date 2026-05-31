# Command Palette (Swift)

Mirrors `../palette.md`. Three layers: hotkey, panel window, command registry.

## CommandRegistry (`Core/CommandRegistry.swift`)

```swift
struct Command: Identifiable {
    let id: String                                  // e.g. "pomodoro.toggle"
    let title: String
    let group: String?
    let keywords: [String]
    let dangerous: Bool
    let when: () -> Bool                            // visibility predicate
    let subtitle: () -> String?                     // dynamic — reads live state
    let run: () async -> Void
}

@MainActor
final class CommandRegistry {
    static let shared = CommandRegistry()
    private(set) var commands: [Command] = []
    func register(_ cmd: Command) { ... }
    func registerMany(_ cmds: [Command]) { ... }
    func applicable() -> [Command] { commands.filter { $0.when() } }
    func find(id: String) -> Command? { ... }
}
```

Identical shape to Electron's `CommandRegistry.ts` — palette and URL-scheme handler
are read-only consumers (preserves ADR-009).

## Hotkey (`Core/HotKey.swift`)

The Carbon `RegisterEventHotKey` API is the only system-wide hotkey path that works
without monitoring all key events:

```swift
import Carbon.HIToolbox

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: () -> Void = {}

    func install(keyCombo: KeyCombo, handler: @escaping () -> Void) throws {
        self.handler = handler
        var hkRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCombo.keyCode),
            UInt32(keyCombo.carbonModifiers),
            EventHotKeyID(signature: OSType(0x4E455855), id: 1),  // 'NEXU'
            GetApplicationEventTarget(),
            0, &hkRef
        )
        guard status == noErr, let hkRef else { throw HotKeyError.registerFailed }
        self.ref = hkRef
        installAppEventHandler()  // calls self.handler on hotkey event
    }

    func uninstall() { if let ref { UnregisterEventHotKey(ref) } }
}
```

The `KeyCombo` parses `cfg.hotkey.palette` strings like `"CommandOrControl+Shift+Space"`
into `(keyCode, modifiers)`. On config hot-reload, uninstall + reinstall.

If registration fails (another app holds the combo): log error, surface a banner in
Settings → Hotkey, app continues to run (matches ADR-010).

## PaletteWindow (`Palette/PaletteWindow.swift`)

NSPanel subclass — directly equivalent to Electron's `type: 'panel'` (ADR-013):

```swift
final class PaletteWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver        // floats above full-screen apps
        isFloatingPanel = true
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true     // shows without [NSApp activate]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(rootView: PaletteView())
    }

    override var canBecomeKey: Bool { true }   // accept keyboard
    override var canBecomeMain: Bool { false }
}
```

Position: centered horizontally, **22% from the top** of the active display's visible
frame. Active display = the one containing `NSEvent.mouseLocation`. Compute on every
`show()` so it follows the user's current screen.

`hidesOnDeactivate = true` + `nonactivatingPanel` is what gives us the "summon → use →
dismiss" pattern Raycast/Spotlight users expect, without dragging MainWindow to the
foreground (the bug ADR-013 fixed).

## PaletteView (SwiftUI)

```swift
struct PaletteView: View {
    @State private var query = ""
    @State private var selection = 0
    @Environment(CommandRegistry.self) private var registry
    @FocusState private var searchFocused: Bool

    var matches: [Command] {
        let pool = registry.applicable()
        return query.isEmpty ? pool : PaletteSearch.score(pool, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search Nexus…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($searchFocused)
                .padding(16)
            Divider()
            List(Array(matches.enumerated()), id: \.element.id) { index, cmd in
                CommandRow(cmd: cmd, isSelected: index == selection)
                    .onTapGesture { run(cmd) }
            }
            Divider()
            FooterView(matchCount: matches.count, message: lastMessage)
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 640, height: 420)
        .onAppear { searchFocused = true; selection = 0 }
        .onKeyPress(.upArrow)   { selection = max(0, selection - 1); return .handled }
        .onKeyPress(.downArrow) { selection = min(matches.count - 1, selection + 1); return .handled }
        .onKeyPress(.return)    { if let cmd = matches[safe: selection] { run(cmd) }; return .handled }
        .onKeyPress(.escape)    { dismiss(); return .handled }
    }
}
```

Note: SwiftUI `.onKeyPress` requires macOS 14+. On macOS 13, fall back to an
`NSViewRepresentable` key handler. Targeting macOS 13 means we ship the fallback by
default.

## Search (`Palette/PaletteSearch.swift`)

Same scoring as Electron palette: substring-first, subsequence fallback, ranked by
field (title > group > keywords > subtitle).

```swift
enum PaletteSearch {
    static func score(_ commands: [Command], query: String) -> [Command] { ... }
    private static func fieldScore(_ haystack: String, _ needle: String) -> Double {
        if haystack.range(of: needle, options: .caseInsensitive) != nil { return 1.0 }
        return subsequenceScore(haystack, needle)
    }
}
```

Empty query → return all `applicable()` commands as-is (VSCode-style discoverability).

## URL Scheme (`Core/URLScheme.swift`)

`nexus://command/<id>?<args>` — handled by `NSAppleEventManager`:

```swift
final class URLScheme: NSObject {
    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handle(_ event: NSAppleEventDescriptor,
                      withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?
            .stringValue,
              let url = URL(string: urlString),
              url.scheme == "nexus", url.host == "command"
        else { return }

        let id = String(url.path.dropFirst())     // "/pomodoro.start" → "pomodoro.start"
        let args = url.queryParams                  // [String: String]
        Task { @MainActor in
            guard let cmd = CommandRegistry.shared.find(id: id) else { return }
            if cmd.dangerous { /* TODO: confirm UI — same TODO as Electron */ }
            await cmd.run()
        }
    }
}
```

`Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>site.easonsi.nexus</string>
    <key>CFBundleURLSchemes</key>
    <array><string>nexus</string></array>
  </dict>
</array>
```

Single-instance lock is automatic for macOS bundled apps — re-launching the
already-running `Nexus.app` simply forwards the URL via Apple Events.

## Registered commands

Same set as `../palette.md`. The Swift-side feature modules each export a
`registerCommands(into: CommandRegistry)` function called from `AppEnvironment.bootstrap()`:

```swift
PomodoroCommands.register(into: registry, service: pomodoro)
TrackerCommands.register(into: registry, service: tracker)
UploaderCommands.register(into: registry, service: uploader)
WindowCommands.register(into: registry, mainWindow: mainWindow)
AppCommands.register(into: registry)   // app.quit, etc.
```

The Electron palette command table (`palette.md` § "Registered commands") transfers
1:1.

## Focus restoration

Because the palette is `nonactivatingPanel`, summoning it never activates Nexus.
Dismissal: `palette.orderOut(nil)`. We deliberately never call `NSApp.hide(nil)` —
that would hide MainWindow if open, the same latent bug ADR-013 fixed in Electron.

The footer "home" icon → `WindowCommands.openMain` (opens MainWindow + activates
Nexus). This is the single path where summoning the palette eventually leads to
Nexus becoming active, and it requires an explicit user action.
