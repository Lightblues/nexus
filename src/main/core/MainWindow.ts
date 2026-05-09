import { BrowserWindow } from 'electron'
import { join } from 'path'
import { is } from '@electron-toolkit/utils'
import { logger } from './Logger'
import { windowStateManager, WindowState } from './WindowStateManager'

class MainWindow {
  private window: BrowserWindow | null = null
  private currentRoute: string = '/stats'
  private saveTimer: NodeJS.Timeout | null = null

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
    const savedState = windowStateManager.load()

    const opts: Electron.BrowserWindowConstructorOptions = {
      width: savedState?.width ?? 900,
      height: savedState?.height ?? 600,
      minWidth: 700,
      minHeight: 400,
      show: false,
      frame: true,
      resizable: true,
      title: 'Nexus',
      webPreferences: {
        preload: join(__dirname, '../preload/index.js'),
        contextIsolation: true,
        sandbox: true
      }
    }
    if (savedState) {
      opts.x = savedState.x
      opts.y = savedState.y
    }

    this.window = new BrowserWindow(opts)

    if (savedState?.isMaximized) {
      this.window.maximize()
    }

    this.window.on('close', () => {
      this.saveState()
    })

    this.window.on('closed', () => {
      this.window = null
    })

    this.window.on('resize', () => this.debounceSave())
    this.window.on('move', () => this.debounceSave())

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

  private debounceSave(): void {
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.saveState(), 500)
  }

  private saveState(): void {
    if (!this.window || this.window.isDestroyed()) return
    const isMaximized = this.window.isMaximized()
    const bounds = isMaximized ? this.window.getNormalBounds() : this.window.getBounds()
    const state: WindowState = {
      x: bounds.x,
      y: bounds.y,
      width: bounds.width,
      height: bounds.height,
      isMaximized
    }
    windowStateManager.save(state)
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
