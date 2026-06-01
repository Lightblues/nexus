import AppKit
import SwiftUI

/// NSPanel subclass — non-activating, floats above all apps including full-screen.
/// Mirrors the role Electron `type: 'panel'` plays in ADR-013: showing this
/// window does NOT call [NSApp activate], so the user's previously-active app
/// keeps its activation. Dismissing the palette via `orderOut` likewise leaves
/// activation alone.
final class PalettePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Float above full-screen apps + appear on every Space.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Allow keyboard input even though we're a panel.
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
