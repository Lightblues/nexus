import AppKit
import SwiftUI
import Combine

/// Owns the singleton PalettePanel and the show/hide lifecycle.
/// Exposes `toggle()` for the global hotkey to call.
@MainActor
final class PaletteController: ObservableObject {
    private var panel: PalettePanel?
    private weak var environment: AppEnvironment?

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
        // Notify the SwiftUI view to focus the search field + reset state.
        NotificationCenter.default.post(name: .paletteDidShow, object: nil)
    }

    func hide() {
        panel?.orderOut(nil)
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
