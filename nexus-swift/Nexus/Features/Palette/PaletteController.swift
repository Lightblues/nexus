import AppKit
import SwiftUI
import Combine

/// Owns the singleton PalettePanel and the show/hide lifecycle.
/// Exposes `toggle()` for the global hotkey to call.
@MainActor
final class PaletteController: ObservableObject {
    private var panel: PalettePanel?
    private weak var environment: AppEnvironment?
    /// Monitors clicks anywhere outside our app while the panel is up.
    private var globalClickMonitor: Any?
    /// Monitors clicks inside our app — needed because `addGlobalMonitor` only
    /// fires for events outside the current app, and the user might click on
    /// the menu bar or another Nexus window.
    private var localClickMonitor: Any?

    func attach(environment: AppEnvironment) {
        self.environment = environment
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        positionOnActiveScreen(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickOutsideMonitors()
        // Notify the SwiftUI view to focus the search field + reset state.
        NotificationCenter.default.post(name: .paletteDidShow, object: nil)
    }

    func hide() {
        panel?.orderOut(nil)
        removeClickOutsideMonitors()
    }

    // MARK: - Click-outside dismissal

    /// Because the palette is a non-activating panel, macOS doesn't give us a
    /// "lost focus → resign key" signal when the user clicks elsewhere. We
    /// install two NSEvent monitors:
    ///   - global: catches clicks in any other app
    ///   - local:  catches clicks in our own app (menu bar, MainWindow, etc.)
    /// Either fires → dismiss.
    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            // Global monitor only fires for events outside our app — any hit
            // here means the user clicked into another app.
            Task { @MainActor in self?.hide() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            // Local monitor fires for events in our app. If the click is on
            // the palette itself, leave it alone; if it's on any other Nexus
            // window (menu bar status item, MainWindow), dismiss.
            guard let self else { return event }
            if event.window === self.panel {
                return event   // user is interacting with the palette — keep it open
            }
            self.hide()
            return event       // let the click through to its target
        }
    }

    private func removeClickOutsideMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localClickMonitor  { NSEvent.removeMonitor(m); localClickMonitor = nil }
    }

    // MARK: - Internals

    private func makePanel() -> PalettePanel {
        guard let env = environment else { fatalError("PaletteController: environment not attached") }
        let p = PalettePanel()
        let root = PaletteView(onDismiss: { [weak self] in self?.hide() })
            .environmentObject(env.pomodoro)
            .environmentObject(env.pomodoroRepository)
            .environmentObject(env.tracker)
            .environmentObject(CommandRegistry.shared)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        // Round the corners so the SwiftUI material chrome shows through cleanly.
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        p.contentView = host
        return p
    }

    /// Center horizontally, position at ~22% from the top of the active screen
    /// (roughly where Spotlight and Raycast sit).
    private func positionOnActiveScreen(_ panel: PalettePanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - frame.height * 0.22 - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

extension Notification.Name {
    static let paletteDidShow = Notification.Name("site.easonsi.nexus.paletteDidShow")
}
