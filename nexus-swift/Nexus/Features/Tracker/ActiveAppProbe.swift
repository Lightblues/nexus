import Foundation
import AppKit
import ApplicationServices

/// Front-window probe via AX API. Replaces the Electron osascript poll.
///
/// Cost on M-series: ~0.3-1ms per call vs ~50ms for `osascript -e ...`. Uses the
/// already-granted Accessibility permission; no extra prompts.
@MainActor
enum ActiveAppProbe {
    /// Friendly display name for Electron-based apps that report themselves as
    /// "Electron" via NSRunningApplication.localizedName. Same map as TrackerService.ts.
    private static let bundleToAppName: [String: String] = [
        "com.microsoft.VSCode": "Code",
        "com.microsoft.VSCodeInsiders": "Code - Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor"
    ]

    /// Returns the active probe, or nil if nothing is focused / AX denied.
    /// Does NOT prompt for permission — caller decides when to prompt.
    static func fetch() -> ActiveProbe? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let bundleId = app.bundleIdentifier
        // Use friendly name when bundleId is known; otherwise localizedName.
        let appName: String
        if let bid = bundleId, let mapped = bundleToAppName[bid] {
            appName = mapped
        } else {
            appName = app.localizedName ?? bundleId ?? "Unknown"
        }

        let title = focusedWindowTitle(pid: pid)

        return ActiveProbe(app: appName, bundleId: bundleId, title: title, url: nil)
    }

    /// Read the focused-window title via AX. Returns nil when:
    ///  - AX permission not granted
    ///  - app has no focused window (Finder desktop, fullscreen system overlay)
    ///  - app blocks AX (rare; some games)
    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        var focusedRef: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &focusedRef)
        guard err == .success, let window = focusedRef else { return nil }
        var titleRef: AnyObject?
        let titleErr = AXUIElementCopyAttributeValue(
            window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
        guard titleErr == .success, let title = titleRef as? String else { return nil }
        return title.isEmpty ? nil : title
    }
}
