import { BrowserWindow } from 'electron'
import { join } from 'path'
import { is } from '@electron-toolkit/utils'
import { logger } from './Logger'

class MainWindow {
  private window: BrowserWindow | null = null
  private currentRoute: string = '/stats'

  show(): void {
    this.showWithRoute('/stats')
  }

  showWithRoute(route: string): void {
    if (this.window && !this.window.isDestroyed()) {
      // Navigate to route (sidebar handles internal navigation)
      if (this.currentRoute !== route) {
        this.currentRoute = route
        this.navigateToRoute(route)
      }
      this.window.focus()
      return
    }
    this.currentRoute = route
    this.create(route)
  }

  private navigateToRoute(route: string): void {
    if (!this.window) return
    // Send hash change to renderer for sidebar navigation
    this.window.webContents.executeJavaScript(`window.location.hash = '#${route}'`)
  }

  private create(route: string): void {

    this.window = new BrowserWindow({
      width: 900,
      height: 600,
      minWidth: 700,
      minHeight: 400,
      show: false,
      frame: true,
      resizable: true,
      title: 'EA Nexus',
      webPreferences: {
        preload: join(__dirname, '../preload/index.js'),
        contextIsolation: true,
        sandbox: true
      }
    })

    this.window.on('closed', () => {
      this.window = null
    })

    this.window.once('ready-to-show', () => {
      this.window?.show()
    })

    // Load with initial route
    if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
      this.window.loadURL(`${process.env['ELECTRON_RENDERER_URL']}#${route}`)
    } else {
      this.window.loadFile(join(__dirname, '../renderer/index.html'), { hash: route })
    }
    logger.info('MainWindow created', { route })
  }

  hide(): void {
    if (this.window && !this.window.isDestroyed()) {
      this.window.hide()
    }
  }

  toggle(): void {
    if (this.window && !this.window.isDestroyed() && this.window.isVisible()) {
      this.hide()
    } else {
      this.show()
    }
  }

  getWindow(): BrowserWindow | null {
    return this.window
  }

  destroy(): void {
    if (this.window && !this.window.isDestroyed()) {
      this.window.destroy()
      this.window = null
    }
  }
}

export const mainWindow = new MainWindow()
