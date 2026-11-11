import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter. Mirrors the Electron `Notification`
/// usage in PomodoroService.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()
    /// Memory-pressure notifications carry one action, "Open Activity Monitor" (inform only).
    nonisolated static let memoryCategory = "memory.pressure"
    nonisolated static let openActivityMonitorAction = "memory.openActivityMonitor"

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: Self.openActivityMonitorAction, title: "Open Activity Monitor", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.memoryCategory, actions: [open], intentIdentifiers: [], options: []),
        ])
    }

    /// Fire-and-forget notification. Requests permission lazily on first call.
    func notify(title: String, body: String, sound: Bool = true, category: String? = nil) {
        Task {
            let granted = await Permissions.requestNotifications()
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            if let category { content.categoryIdentifier = category }
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

    /// The action button, or a click on the body of a memory notification, opens Activity Monitor.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        if category == Self.memoryCategory,
           action == Self.openActivityMonitorAction || action == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in MemoryWatchService.openActivityMonitor() }
        }
        handler()
    }
}
