import { systemPreferences, dialog, shell, Notification } from 'electron'
import { logger } from './Logger'

type PermissionStatus = 'authorized' | 'denied' | 'restricted' | 'not-determined'

class PermissionManager {
  private accessibilityStatus: PermissionStatus = 'not-determined'
  private hasShownNotification = false

  /** Check accessibility permission status (required for window tracking) */
  checkAccessibility(): PermissionStatus {
    // Note: systemPreferences.isTrustedAccessibilityClient only returns boolean
    // We use it to check current state without triggering a prompt
    const isTrusted = systemPreferences.isTrustedAccessibilityClient(false)
    this.accessibilityStatus = isTrusted ? 'authorized' : 'denied'
    logger.info('Accessibility permission status', { status: this.accessibilityStatus })
    return this.accessibilityStatus
  }

  /** Check if accessibility is granted */
  hasAccessibility(): boolean {
    return this.accessibilityStatus === 'authorized'
  }

  /** Show one-time notification if permission is missing */
  notifyMissingPermission(): void {
    if (this.hasShownNotification || this.hasAccessibility()) return
    this.hasShownNotification = true

    // Show system notification
    if (Notification.isSupported()) {
      const notification = new Notification({
        title: 'EA Nexus - Permission Required',
        body: 'Time Tracker needs Accessibility permission. Click to open Settings.',
        silent: false
      })
      notification.on('click', () => this.openAccessibilitySettings())
      notification.show()
    }

    // Also show a dialog for clearer instructions
    dialog
      .showMessageBox({
        type: 'info',
        title: 'Permission Required',
        message: 'Time Tracker requires Accessibility permission',
        detail:
          'To track active windows, EA Nexus needs Accessibility permission.\n\n' +
          '1. Click "Open Settings" to open System Settings\n' +
          '2. Find and enable "EA Nexus" in the list\n' +
          '3. Restart EA Nexus for changes to take effect\n\n' +
          'Time Tracker will be disabled until permission is granted.',
        buttons: ['Open Settings', 'Later'],
        defaultId: 0
      })
      .then((result) => {
        if (result.response === 0) {
          this.openAccessibilitySettings()
        }
      })
  }

  /** Open System Settings to Accessibility pane */
  openAccessibilitySettings(): void {
    // macOS Ventura and later use this URL
    shell.openExternal(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
    )
  }
}

export const permissionManager = new PermissionManager()
