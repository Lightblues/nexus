import { app, BrowserWindow, screen } from 'electron'
import { join } from 'path'
import { is } from '@electron-toolkit/utils'
import { logger } from './Logger'
import { popupWindow } from './PopupWindow'

const WIDTH = 640
const HEIGHT = 420

class PaletteWindow {
  private window: BrowserWindow | null = null

  create(): void {
    this.window = new BrowserWindow({
      width: WIDTH,
      height: HEIGHT,
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

    // macOS: float above full-screen apps like Spotlight / Raycast
    if (process.platform === 'darwin') {
      this.window.setAlwaysOnTop(true, 'screen-saver')
      this.window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
    }

    this.window.on('blur', () => this.hide())

    if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
      this.window.loadURL(`${process.env['ELECTRON_RENDERER_URL']}#/palette`)
    } else {
      this.window.loadFile(join(__dirname, '../renderer/index.html'), {
        hash: '/palette'
      })
    }

    logger.info('PaletteWindow created')
  }

  toggle(): void {
    if (!this.window) return
    if (this.window.isVisible()) this.hide()
    else this.show()
  }

  show(): void {
    if (!this.window) return

    // Close tray popover if open — palette takes over as the primary surface
    popupWindow.hide()

    const cursor = screen.getCursorScreenPoint()
    const display = screen.getDisplayNearestPoint(cursor)
    const area = display.workArea

    // Center horizontally, place slightly above vertical center (Raycast-like)
    const x = Math.round(area.x + (area.width - WIDTH) / 2)
    const y = Math.round(area.y + area.height * 0.22)

    this.window.setPosition(x, y)
    this.window.show()
    this.window.focus()
  }

  hide(): void {
    if (this.window && this.window.isVisible()) {
      this.window.hide()
      // Return focus to the previously active app (macOS)
      if (process.platform === 'darwin') app.hide()
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

export const paletteWindow = new PaletteWindow()
