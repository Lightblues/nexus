import AppKit
import SwiftUI

/// Owns the lazily-created main window. Singleton-style, held by AppEnvironment.
/// The window is built on first show; closing just hides (sets `isReleasedWhenClosed = false`).
@MainActor
final class MainWindowController: NSObject {
    /// Pending route to apply on next show. Read by MainWindowView via env object.
    let routeRequest = RouteRequest()

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

    /// Show the window and switch to the requested route.
    func show(route: MainRoute) {
        routeRequest.requested = route
        show()
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
            .environmentObject(env.uploader)
            .environmentObject(env.uploaderRepository)
            .environmentObject(routeRequest)
            .environmentObject(routeRequest)
        let host = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 900, height: 600))
        win.minSize = NSSize(width: 700, height: 400)
        win.title = "Nexus"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        // AppKit autosave persists frame to UserDefaults under this key.
        // Window geometry is per-machine UI state, which is what UserDefaults
        // is for (~/Library/Preferences/site.easonsi.nexus.plist).
        win.setFrameAutosaveName("MainWindow")
        // First-launch fallback if no saved frame exists.
        if win.frame.size.width < 100 {
            win.setContentSize(NSSize(width: 900, height: 600))
            win.center()
        }
        win.delegate = self
        return win
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        didClose()
    }
}

/// Lightweight observable used to push route changes from CommandRegistry into
/// MainWindowView's selection. `requested` is consumed (set to nil) once the
/// view applies it.
@MainActor
final class RouteRequest: ObservableObject {
    @Published var requested: MainRoute?
}
