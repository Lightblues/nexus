import { ipcMain, BrowserWindow } from 'electron'
import { uploaderService } from './UploaderService'
import { getImageMeta } from './ImageCompressor'
import { trayManager } from '../../core/TrayManager'

export function registerUploaderIPC(): void {
  // Listen for images dropped on tray and store as pending
  trayManager.on('image-dropped', (data: { buffer: number[]; filename: string }) => {
    // Store in service for UploaderView to retrieve when it mounts
    uploaderService.setPendingImage(data)
    // Also send to all windows (for cases where UploaderView is already mounted)
    BrowserWindow.getAllWindows().forEach((win) => {
      win.webContents.send('uploader:image-dropped', data)
    })
  })

  ipcMain.handle('uploader:get-pending-image', () => {
    return uploaderService.getPendingImage()
  })

  ipcMain.handle('uploader:get-config', () => {
    return uploaderService.getConfig()
  })

  ipcMain.handle('uploader:get-clipboard-image', async () => {
    const image = await uploaderService.getClipboardImage()
    if (!image) return null
    return {
      buffer: Array.from(image.buffer),
      format: image.format,
      width: image.width,
      height: image.height,
      size: image.size
    }
  })

  ipcMain.handle('uploader:get-image-meta', async (_event, bufferArray: number[]) => {
    const buffer = Buffer.from(bufferArray)
    return getImageMeta(buffer)
  })

  ipcMain.handle(
    'uploader:compress',
    async (_event, bufferArray: number[], quality: number, format: 'auto' | 'webp' | 'jpeg' | 'png') => {
      const buffer = Buffer.from(bufferArray)
      const result = await uploaderService.compressImage(buffer, quality, format)
      return {
        buffer: Array.from(result.buffer),
        originalSize: result.originalSize,
        compressedSize: result.compressedSize,
        width: result.width,
        height: result.height,
        outputFormat: result.outputFormat
      }
    }
  )

  ipcMain.handle(
    'uploader:upload',
    async (
      _event,
      bufferArray: number[],
      filename: string,
      path: string,
      meta: { width: number; height: number; format: string; originalSize: number }
    ) => {
      const buffer = Buffer.from(bufferArray)
      return uploaderService.upload(buffer, filename, path, meta)
    }
  )

  ipcMain.handle('uploader:delete', async (_event, id: string) => {
    return uploaderService.deleteRecord(id)
  })

  ipcMain.handle('uploader:get-history', () => {
    return uploaderService.getHistory()
  })

  ipcMain.handle('uploader:get-recent-paths', () => {
    return uploaderService.getRecentPaths()
  })

  ipcMain.handle('uploader:copy-url', (_event, url: string) => {
    uploaderService.copyToClipboard(url)
    return { success: true }
  })

  ipcMain.handle('uploader:get-thumbnail', (_event, id: string) => {
    const thumbnail = uploaderService.getThumbnail(id)
    return thumbnail ? Array.from(thumbnail) : null
  })
}
