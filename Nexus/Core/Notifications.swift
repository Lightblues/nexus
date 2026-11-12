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
    /// One memory notification at a time; the newer replaces it, the return to normal removes it.
    nonisolated static let memoryID = "memory.pressure"
    /// Pomodoro completion: one notification at a time under a fixed id, removed when the state moves on.
    nonisolated static let pomodoroID = "pomodoro.completion"
    nonisolated static let breakDoneCategory = "pomodoro.breakDone"
    nonisolated static let startFocusAction = "pomodoro.startFocus"
    /// Starts a focus session; set by `PomodoroService`. Called for "Start Focus" or a click on the body.
    var onStartFocus: (() -> Void)?
    /// Bumped by `remove`, so a `notify` still awaiting permission does not post after its withdrawal.
    private var generation: [String: Int] = [:]

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: Self.openActivityMonitorAction, title: "Open Activity Monitor", options: [.foreground])
        // No `.foreground`: starting focus from the notification leaves the current app in front.
        let start = UNNotificationAction(identifier: Self.startFocusAction, title: "Start Focus", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.memoryCategory, actions: [open], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.breakDoneCategory, actions: [start], intentIdentifiers: [], options: []),
        ])
    }

    /// Fire-and-forget notification. Requests permission lazily on first call.
    /// A fixed `identifier` replaces the earlier notification with that id instead of adding another.
    func notify(title: String, body: String, sound: Bool = true, category: String? = nil, identifier: String? = nil) {
        let gen = identifier.map { generation[$0, default: 0] }
        Task {
            let granted = await Permissions.requestNotifications()
            guard granted else { return }
            if let identifier, generation[identifier, default: 0] != gen { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            if let category { content.categoryIdentifier = category }
            let request = UNNotificationRequest(
                identifier: identifier ?? UUID().uuidString,
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

    /// Withdraws a delivered (or pending) notification, e.g. once the state it reports is over.
    func remove(identifier: String) {
        generation[identifier, default: 0] += 1
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
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

    /// The action button, or a click on the body, opens Activity Monitor (memory) or starts focus (break done).
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
        } else if category == Self.breakDoneCategory,
                  action == Self.startFocusAction || action == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in NotificationService.shared.onStartFocus?() }
        }
        handler()
    }
}
