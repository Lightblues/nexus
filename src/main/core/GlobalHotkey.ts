import { globalShortcut } from 'electron'
import { configManager } from './ConfigManager'
import { paletteWindow } from './PaletteWindow'
import { logger } from './Logger'

class GlobalHotkey {
  private registered: string | null = null

  register(): void {
    const accelerator = configManager.get().hotkey.palette
    this.registerAccelerator(accelerator)
  }

  /** Re-register when config changes (called from config:updated handler). */
  reload(): void {
    const accelerator = configManager.get().hotkey.palette
    if (accelerator === this.registered) return
    this.unregister()
    this.registerAccelerator(accelerator)
  }

  unregister(): void {
    if (this.registered) {
      globalShortcut.unregister(this.registered)
      this.registered = null
    }
  }

  destroy(): void {
    globalShortcut.unregisterAll()
    this.registered = null
  }

  private registerAccelerator(accelerator: string): void {
    if (!accelerator) {
      logger.warn('Palette hotkey is empty; skipped')
      return
    }
    const ok = globalShortcut.register(accelerator, () => paletteWindow.toggle())
    if (!ok) {
      logger.error('Failed to register palette hotkey', { accelerator })
      return
    }
    this.registered = accelerator
    logger.info('Palette hotkey registered', { accelerator })
  }
}

export const globalHotkey = new GlobalHotkey()
