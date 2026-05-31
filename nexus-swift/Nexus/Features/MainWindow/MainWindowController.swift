import AppKit
import SwiftUI

/// Owns the lazily-created main window. Singleton-style, held by AppEnvironment.
/// The window is built on first show; closing just hides (sets `isReleasedWhenClosed = false`).
@MainActor
final class MainWindowController: NSObject {
    private var window: NSWindow?
    private weak var environment: AppEnvironment?

    func attach(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        // Make sure Nexus has Dock-style activation while a real window is up,
        // so cmd-tab and clicking outside work as users expect.
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called by NSWindowDelegate when the user closes the main window.
    func didClose() {
        // Drop back to accessory so we vanish from the Dock + ⌘Tab,
        // matching the menu-bar-app feel from `LSUIElement = true`.
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Build

    private func makeWindow() -> NSWindow {
        guard let env = environment else { fatalError("MainWindowController: environment not attached") }
        let root = MainWindowView()
            .environmentObject(env.config)
            .environmentObject(env.pomodoro)
            .environmentObject(env.pomodoroRepository)
            .environmentObject(env.trackerRepository)
            .environmentObject(env.tracker)
        let host = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 900, height: 600))
        win.minSize = NSSize(width: 700, height: 400)
        win.title = "Nexus"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        return win
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        didClose()
    }
}
