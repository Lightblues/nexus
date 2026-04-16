import { clipboard } from 'electron'
import { v4 as uuidv4 } from 'uuid'
import { configManager } from '../../core/ConfigManager'
import { logger } from '../../core/Logger'
import { compressImage, getImageMeta } from './ImageCompressor'
import { githubUploader } from './GitHubUploader'
import { uploaderDataManager } from './UploaderDataManager'
import type { UploaderConfig, UploadRecord, UploadResult } from '@shared/types'
import type { ImageMetaMain, CompressResultMain } from './types'

class UploaderService {
  private config: UploaderConfig | null = null
  private pendingImage: { buffer: number[]; filename: string } | null = null

  init(): void {
    uploaderDataManager.init()
    this.loadConfig()
    configManager.on('config:updated', () => this.loadConfig())
  }

  private loadConfig(): void {
    const cfg = configManager.get() as { uploader?: UploaderConfig }
    if (cfg.uploader) {
      this.config = cfg.uploader
      if (this.config.github.token) {
        githubUploader.configure(this.config.github)
      }
    }
  }

  getConfig(): UploaderConfig | null {
    return this.config
  }

  async getClipboardImage(): Promise<ImageMetaMain | null> {
    try {
      const image = clipboard.readImage()
      if (image.isEmpty()) {
        return null
      }
      const buffer = image.toPNG()
      const meta = await getImageMeta(buffer)
      return {
        buffer,
        format: meta.format,
        width: meta.width,
        height: meta.height,
        size: buffer.length
      }
    } catch (err) {
      logger.error('Failed to read clipboard image', err)
      return null
    }
  }

  async compressImage(
    buffer: Buffer,
    quality: number,
    format: 'auto' | 'webp' | 'jpeg' | 'png' = 'auto'
  ): Promise<CompressResultMain & { outputFormat: string }> {
    return compressImage(buffer, quality, format)
  }

  async upload(
    buffer: Buffer,
    filename: string,
    path: string,
    meta: { width: number; height: number; format: string; originalSize: number }
  ): Promise<UploadResult & { record?: UploadRecord }> {
    if (!this.config) {
      return { success: false, error: 'Uploader not configured' }
    }
    const result = await githubUploader.upload(buffer, path, filename, this.config.cdn.baseUrl)
    if (!result.success) {
      return result
    }

    const record: UploadRecord = {
      id: uuidv4(),
      filename,
      originalName: filename,
      timestamp: new Date().toISOString(),
      originalSize: meta.originalSize,
      compressedSize: buffer.length,
      width: meta.width,
      height: meta.height,
      format: meta.format as 'png' | 'jpeg' | 'webp' | 'gif',
      path,
      cdnUrl: result.cdnUrl!,
      sha: result.sha!
    }
    // Save with thumbnail if enabled
    if (this.config.cacheThumbnails) {
      await uploaderDataManager.addRecord(record, buffer)
    } else {
      await uploaderDataManager.addRecord(record)
    }
    return { ...result, record }
  }

  async deleteRecord(id: string): Promise<{ success: boolean; error?: string }> {
    const record = uploaderDataManager.getRecord(id)
    if (!record) {
      return { success: false, error: 'Record not found' }
    }
    const fullPath = record.path ? `${record.path}/${record.filename}` : record.filename
    const result = await githubUploader.delete(fullPath, record.sha)
    if (result.success) {
      uploaderDataManager.removeRecord(id)
    }
    return result
  }

  getHistory(): UploadRecord[] {
    return uploaderDataManager.getHistory()
  }

  getRecentPaths(): string[] {
    return uploaderDataManager.getRecentPaths()
  }

  copyToClipboard(text: string): void {
    clipboard.writeText(text)
  }

  setPendingImage(data: { buffer: number[]; filename: string }): void {
    this.pendingImage = data
  }

  getPendingImage(): { buffer: number[]; filename: string } | null {
    const image = this.pendingImage
    this.pendingImage = null // Clear after retrieval
    return image
  }

  getThumbnail(id: string): Buffer | null {
    const thumbPath = uploaderDataManager.getThumbnailPath(id)
    if (!thumbPath) return null
    try {
      return require('fs').readFileSync(thumbPath)
    } catch {
      return null
    }
  }
}

export const uploaderService = new UploaderService()
