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
    private var clickOutsideMonitor: Any?

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

            // Overlay an invisible view that receives image drops while
            // forwarding clicks to the button (hitTest returns nil). Drag an
            // image onto the icon → uploader opens with the image preloaded.
            // Multi-file drops route through as a batch.
            let overlay = StatusItemDropView(frame: button.bounds) { [weak self] payloads in
                self?.handleStatusItemDrop(payloads: payloads)
            }
            overlay.autoresizingMask = [.width, .height]
            button.addSubview(overlay)
        }
        statusItem = item
    }

    /// Called from StatusItemDropView when user drops one or more images on
    /// the menu bar icon. We stash them all as pending so the uploader view
    /// (which we open immediately afterwards) picks them up as a batch.
    private func handleStatusItemDrop(payloads: [(Data, String)]) {
        guard !payloads.isEmpty else { return }
        Log.uploader.info("dropped on icon: \(payloads.count) image\(payloads.count == 1 ? "" : "s")")
        let pendings = payloads.map { PendingImage(data: $0.0, filename: $0.1) }
        environment.uploader.setPending(pendings)
        environment.mainWindow.show(route: .uploader)
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
        let mainItem = NSMenuItem(title: "Show Main Window", action: #selector(showMainWindow), keyEquivalent: "")
        menu.addItem(mainItem)
        menu.addItem(.separator())
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

    @objc private func showMainWindow() {
        environment.mainWindow.show()
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
            .environmentObject(environment.pomodoroRepository)
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
            closePopover()
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Intentionally do NOT call `NSApp.activate(ignoringOtherApps: true)` here.
            // The popover is a status-bar attachment and should behave like a system
            // menubar item: appear without stealing focus from the user's current app
            // (e.g. VSCode) and without dragging Nexus's MainWindow z-order to the
            // front. SwiftUI buttons inside the popover work fine without app
            // activation. The only place we *do* need activation is when the user
            // opens the EditSessionModal sheet (TextFields need key focus); that
            // call lives in PomodoroPopoverView's edit button action.
            installClickOutsideMonitor()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeClickOutsideMonitor()
    }

    /// `NSPopover.behavior = .transient` should auto-dismiss on outside clicks, but
    /// it's unreliable when we call `NSApp.activate` ourselves (it skips the
    /// dismiss path for clicks that land on other apps). A global event monitor
    /// catches clicks anywhere outside the app reliably.
    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // Global monitor only fires for events outside our app, so any hit here
            // means the user clicked away → close.
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
