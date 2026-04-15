import { Tray, Menu, nativeImage, app } from 'electron'
import * as fs from 'fs'
import * as path from 'path'
import { EventEmitter } from 'events'
import { logger } from './Logger'
import { popupWindow } from './PopupWindow'
import { mainWindow } from './MainWindow'

class TrayManager extends EventEmitter {
  private tray: Tray | null = null

  init(): void {
    // Create a minimal 16x16 icon (macOS requires valid icon)
    const icon = this.createDefaultIcon()
    this.tray = new Tray(icon)
    this.tray.setTitle('')
    this.tray.setToolTip('EA Nexus')

    // Left click: toggle popover
    this.tray.on('click', (_event, bounds) => {
      popupWindow.toggle(bounds)
    })

    // Right click: context menu
    this.tray.on('right-click', () => {
      const contextMenu = Menu.buildFromTemplate([
        { label: 'Show Main Window', click: () => mainWindow.show() },
        { type: 'separator' },
        { label: 'About EA Nexus', click: () => this.showAbout() },
        { type: 'separator' },
        { label: 'Quit', click: () => app.quit() }
      ])
      this.tray?.popUpContextMenu(contextMenu)
    })

    // Handle file drop on tray icon
    this.tray.on('drop-files', (_event, files) => {
      this.handleDropFiles(files)
    })

    logger.info('TrayManager initialized')
  }

  private handleDropFiles(files: string[]): void {
    const imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp']
    const imageFiles = files.filter((f) => {
      const ext = path.extname(f).toLowerCase()
      return imageExtensions.includes(ext)
    })

    if (imageFiles.length > 0) {
      const filePath = imageFiles[0]
      logger.info(`Image dropped on tray: ${filePath}`)
      try {
        const buffer = fs.readFileSync(filePath)
        const filename = path.basename(filePath)
        this.emit('image-dropped', { buffer: Array.from(buffer), filename })
        // Show popup window for upload confirmation
        if (this.tray) {
          popupWindow.show(this.tray.getBounds())
        }
      } catch (err) {
        logger.error('Failed to read dropped image', err)
      }
    }
  }

  setTitle(title: string): void {
    if (this.tray) {
      this.tray.setTitle(title)
    }
  }

  private showAbout(): void {
    const { dialog } = require('electron')
    const version = app.getVersion()
    dialog.showMessageBox({
      type: 'info',
      title: 'About EA Nexus',
      message: 'EA Nexus',
      detail: `macOS Menu Bar Agent\nVersion ${version}`
    })
  }

  destroy(): void {
    if (this.tray) {
      this.tray.destroy()
      this.tray = null
    }
  }

  private createDefaultIcon(): Electron.NativeImage {
    // Create a simple 16x16 template icon for macOS menu bar
    // Using a circle shape as placeholder
    const size = 16
    const canvas = Buffer.alloc(size * size * 4)

    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const idx = (y * size + x) * 4
        const cx = size / 2, cy = size / 2, r = 5
        const dist = Math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        if (dist <= r) {
          canvas[idx] = 0       // R
          canvas[idx + 1] = 0   // G
          canvas[idx + 2] = 0   // B
          canvas[idx + 3] = 255 // A
        } else {
          canvas[idx + 3] = 0   // Transparent
        }
      }
    }

    const icon = nativeImage.createFromBuffer(canvas, { width: size, height: size })
    icon.setTemplateImage(true) // For macOS dark/light mode
    return icon
  }
}

export const trayManager = new TrayManager()
