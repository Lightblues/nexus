import Foundation
import AppKit
import ApplicationServices
import UserNotifications

/// macOS permission helpers. Wraps the AX, Apple Events, and Notifications APIs.
@MainActor
enum Permissions {
    // MARK: - Accessibility

    /// True if our process is in the AX trusted list.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission. Non-blocking.
    @discardableResult
    static func promptAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Notifications

    static func requestNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Log.app.warn("Notifications request failed: \(error)")
            return false
        }
    }
}
