import SwiftUI

@main
struct NexusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No SwiftUI scenes for v1 — AppDelegate owns the status item + popover.
        // We need at least one Scene for the App protocol; Settings is hidden by
        // LSUIElement=true in Info.plist and the empty body.
        Settings { EmptyView() }
    }
}
