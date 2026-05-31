import Foundation
import AppKit

/// Window + app-level commands. These are owned by MainWindowController so
/// they live alongside the window logic.
@MainActor
enum WindowCommands {
    static func register(mainWindow: MainWindowController) {
        let registry = CommandRegistry.shared
        let g = "Window"

        registry.register(Command(
            id: "window.openMain",
            title: "Open Main Window",
            group: g,
            keywords: ["nexus", "show"],
            run: { [weak mainWindow] in mainWindow?.show() }
        ))

        registry.register(Command(
            id: "window.openStats",
            title: "Open Statistics",
            group: g,
            keywords: ["chart", "calendar", "history"],
            run: { [weak mainWindow] in mainWindow?.show(route: .stats) }
        ))

        registry.register(Command(
            id: "window.openTracker",
            title: "Open Time Tracker",
            group: g,
            keywords: ["activity", "apps"],
            run: { [weak mainWindow] in mainWindow?.show(route: .tracker) }
        ))

        registry.register(Command(
            id: "window.openSettings",
            title: "Open Settings",
            group: g,
            keywords: ["preferences", "config"],
            run: { [weak mainWindow] in mainWindow?.show(route: .settings) }
        ))
    }
}

@MainActor
enum AppCommands {
    static func register() {
        let registry = CommandRegistry.shared

        registry.register(Command(
            id: "app.quit",
            title: "Quit Nexus",
            group: "App",
            dangerous: true,
            run: { NSApp.terminate(nil) }
        ))
    }
}
