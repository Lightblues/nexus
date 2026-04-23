import { ipcMain } from 'electron'
import { IPC } from '@shared/ipc'
import { commandRegistry, paletteWindow, logger } from '../../core'

export function registerPaletteIPC(): void {
  ipcMain.handle(IPC.palette.list, () => {
    return commandRegistry.list()
  })

  ipcMain.handle(IPC.palette.execute, async (_event, id: string) => {
    const result = await commandRegistry.execute(id, { source: 'palette' })
    if (result.closePalette !== false) {
      paletteWindow.hide()
    }
    return result
  })

  ipcMain.handle(IPC.palette.close, () => {
    paletteWindow.hide()
  })

  logger.info('Palette IPC handlers registered')
}
