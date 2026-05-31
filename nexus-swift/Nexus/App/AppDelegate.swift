import AppKit
import SwiftUI

/// AppKit lifecycle owner. Creates the status item, popover, and bootstraps services.
/// We use AppKit (not SwiftUI MenuBarExtra) because:
///  - status item title needs 1Hz writes without re-rendering a SwiftUI label tree
///  - the uploader feature (later) needs a custom drag-drop view on the status button
///  - the palette panel (later) needs a non-activating NSPanel
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run bootstrap and don't block UI.
        Task { @MainActor in
            await environment.bootstrap()
        }

        installStatusItem()
        installPopover()
        environment.pomodoro.attach(statusItem: statusItem!)
        Log.app.info("Nexus (Swift) launched, pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Synchronously block on a final flush — best effort within macOS shutdown timeout.
        let group = DispatchGroup()
        group.enter()
        Task { @MainActor in
            await environment.shutdown()
            group.leave()
        }
        _ = group.wait(timeout: .now() + .seconds(2))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app — never terminate just because windows closed.
        false
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // SF Symbol "timer" as Template image — adapts to dark/light menu bar.
            let image = NSImage(systemSymbolName: "timer",
                                accessibilityDescription: "Nexus")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleStatusButtonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func handleStatusButtonClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Nexus", action: #selector(about), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Reset menu so left-click goes back to popover toggle.
        statusItem?.menu = nil
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Popover

    private func installPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        let root = PomodoroPopoverView()
            .environmentObject(environment.pomodoro)
            .environmentObject(environment.pomodoroStore)
            .environmentObject(environment.config)
        let host = NSHostingController(rootView: root)
        host.view.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        pop.contentViewController = host
        pop.contentSize = NSSize(width: 320, height: 400)
        popover = pop
    }

    private func togglePopover() {
        guard let pop = popover, let button = statusItem?.button else { return }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate so the SwiftUI views can take focus for typing in editor sheet.
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
