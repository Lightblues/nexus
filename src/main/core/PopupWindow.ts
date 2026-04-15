import { BrowserWindow, Rectangle, screen } from 'electron'
import { join } from 'path'
import { is } from '@electron-toolkit/utils'
import { configManager } from './ConfigManager'
import { logger } from './Logger'

class PopupWindow {
  private window: BrowserWindow | null = null
  private lastTrayBounds: Rectangle | null = null

  create(): void {
    const config = configManager.get()
    this.window = new BrowserWindow({
      width: config.ui.windowWidth,
      height: config.ui.windowHeight,
      show: false,
      frame: false,
      resizable: false,
      movable: false,
      minimizable: false,
      maximizable: false,
      closable: false,
      skipTaskbar: true,
      alwaysOnTop: true,
      transparent: true,
      hasShadow: true,
      webPreferences: {
        preload: join(__dirname, '../preload/index.js'),
        contextIsolation: true,
        sandbox: true
      }
    })

    // macOS: Show on all workspaces/desktops to avoid switching spaces when clicking tray
    if (process.platform === 'darwin') {
      this.window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
    }

    // Hide on blur
    this.window.on('blur', () => {
      this.hide()
    })

    // Load renderer
    if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
      this.window.loadURL(process.env['ELECTRON_RENDERER_URL'])
    } else {
      this.window.loadFile(join(__dirname, '../renderer/index.html'))
    }

    logger.info('PopupWindow created')
  }

  toggle(trayBounds: Rectangle): void {
    if (!this.window) return
    if (this.window.isVisible()) {
      this.hide()
    } else {
      this.show(trayBounds)
    }
  }

  show(trayBounds?: Rectangle): void {
    if (!this.window) return
    const bounds = trayBounds || this.lastTrayBounds
    if (!bounds) return

    this.lastTrayBounds = bounds
    const { width } = this.window.getBounds()

    // Calculate position centered below tray icon
    let x = Math.round(bounds.x + bounds.width / 2 - width / 2)
    const y = Math.round(bounds.y + bounds.height)

    // Ensure window stays within screen bounds
    const display = screen.getDisplayNearestPoint({ x: bounds.x, y: bounds.y })
    const screenBounds = display.workArea
    if (x + width > screenBounds.x + screenBounds.width) {
      x = screenBounds.x + screenBounds.width - width
    }
    if (x < screenBounds.x) {
      x = screenBounds.x
    }

    this.window.setPosition(x, y)
    this.window.show()
  }

  // Show without stealing focus (for notifications)
  showInactive(): void {
    if (!this.window || !this.lastTrayBounds) return
    const bounds = this.lastTrayBounds
    const { width } = this.window.getBounds()

    let x = Math.round(bounds.x + bounds.width / 2 - width / 2)
    const y = Math.round(bounds.y + bounds.height)

    const display = screen.getDisplayNearestPoint({ x: bounds.x, y: bounds.y })
    const screenBounds = display.workArea
    if (x + width > screenBounds.x + screenBounds.width) {
      x = screenBounds.x + screenBounds.width - width
    }
    if (x < screenBounds.x) {
      x = screenBounds.x
    }

    this.window.setPosition(x, y)
    this.window.showInactive()
  }

  hide(): void {
    if (this.window && this.window.isVisible()) {
      this.window.hide()
    }
  }

  getWindow(): BrowserWindow | null {
    return this.window
  }

  destroy(): void {
    if (this.window) {
      this.window.destroy()
      this.window = null
    }
  }
}

export const popupWindow = new PopupWindow()
