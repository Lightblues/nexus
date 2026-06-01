import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter. Mirrors the Electron `Notification`
/// usage in PomodoroService.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    func setup() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Fire-and-forget notification. Requests permission lazily on first call.
    func notify(title: String, body: String, sound: Bool = true) {
        Task {
            let granted = await Permissions.requestNotifications()
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Log.app.warn("Notification add failed: \(error)")
            }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when app is foreground.
        handler([.banner, .sound])
    }
}
