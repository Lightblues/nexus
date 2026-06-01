import SwiftUI
import AppKit

@main
struct NexusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI requires at least one Scene per App protocol; the AppDelegate
        // owns all real UI (status item, popover, main window). We use Settings
        // as a trampoline so macOS's standard ⌘, gesture jumps to MainWindow's
        // Settings route instead of presenting an empty window.
        Settings {
            SettingsTrampoline(appDelegate: appDelegate)
        }
    }
}

/// Routes the system-issued "Show Settings" command (⌘,) to MainWindow.
/// Renders nothing; on first appearance it tells AppDelegate to open the
/// Settings tab and dismisses the SwiftUI-spawned trampoline window.
private struct SettingsTrampoline: View {
    let appDelegate: AppDelegate
    @State private var hostWindow: NSWindow?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(WindowAccessor { hostWindow = $0 })
            .onAppear { route() }
            // Re-route every time SwiftUI re-shows the scene (⌘, after the
            // trampoline window was previously closed reopens it).
            .onChange(of: hostWindow) { _ in route() }
    }

    private func route() {
        appDelegate.environment.mainWindow.show(route: .settings)
        // Close the (invisible) SwiftUI Settings window on the next runloop
        // tick so SwiftUI finishes mounting before we tear it down.
        DispatchQueue.main.async {
            hostWindow?.close()
        }
    }
}

/// Tiny NSViewRepresentable that hands back the NSWindow that ends up
/// hosting it. Used by SettingsTrampoline to close the SwiftUI Settings
/// window after routing the user to MainWindow.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onWindow(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}
