import * as fs from 'fs'
import * as path from 'path'
import { pathManager } from '../../core/PathManager'
import { logger } from '../../core/Logger'
import { generateThumbnail } from './ImageCompressor'
import type { UploaderData, UploadRecord } from './types'

const DEFAULT_DATA: UploaderData = {
  version: 1,
  recentPaths: [],
  history: []
}

class UploaderDataManager {
  private data: UploaderData = DEFAULT_DATA
  private dataPath: string
  private cacheDir: string

  constructor() {
    this.dataPath = path.join(pathManager.eaDir, 'uploader.json')
    this.cacheDir = path.join(pathManager.eaDir, 'uploader', 'cache')
  }

  init(): void {
    this.load()
    // Ensure cache directory exists
    if (!fs.existsSync(this.cacheDir)) {
      fs.mkdirSync(this.cacheDir, { recursive: true })
    }
  }

  private load(): void {
    try {
      if (fs.existsSync(this.dataPath)) {
        const content = fs.readFileSync(this.dataPath, 'utf-8')
        this.data = { ...DEFAULT_DATA, ...JSON.parse(content) }
      }
    } catch (err) {
      logger.error('Failed to load uploader data', err)
      this.data = DEFAULT_DATA
    }
  }

  private save(): void {
    try {
      fs.writeFileSync(this.dataPath, JSON.stringify(this.data, null, 2))
    } catch (err) {
      logger.error('Failed to save uploader data', err)
    }
  }

  async addRecord(record: UploadRecord, imageBuffer?: Buffer): Promise<void> {
    this.data.history.unshift(record)
    // Keep only last 100 records
    if (this.data.history.length > 100) {
      const removed = this.data.history.slice(100)
      this.data.history = this.data.history.slice(0, 100)
      // Clean up old thumbnails
      removed.forEach((r) => this.deleteThumbnail(r.id))
    }
    // Update recent paths
    if (record.path && !this.data.recentPaths.includes(record.path)) {
      this.data.recentPaths.unshift(record.path)
      if (this.data.recentPaths.length > 10) {
        this.data.recentPaths = this.data.recentPaths.slice(0, 10)
      }
    }
    // Generate and save thumbnail
    if (imageBuffer) {
      try {
        const thumbnail = await generateThumbnail(imageBuffer, 200)
        const thumbPath = path.join(this.cacheDir, `${record.id}.webp`)
        fs.writeFileSync(thumbPath, thumbnail)
        logger.info(`Thumbnail cached: ${record.id}`)
      } catch (err) {
        logger.error('Failed to generate thumbnail', err)
      }
    }
    this.save()
  }

  removeRecord(id: string): void {
    this.data.history = this.data.history.filter((r) => r.id !== id)
    this.deleteThumbnail(id)
    this.save()
  }

  getHistory(): UploadRecord[] {
    return this.data.history
  }

  getRecentPaths(): string[] {
    return this.data.recentPaths
  }

  getRecord(id: string): UploadRecord | undefined {
    return this.data.history.find((r) => r.id === id)
  }

  getThumbnailPath(id: string): string | null {
    const thumbPath = path.join(this.cacheDir, `${id}.webp`)
    return fs.existsSync(thumbPath) ? thumbPath : null
  }

  private deleteThumbnail(id: string): void {
    const thumbPath = path.join(this.cacheDir, `${id}.webp`)
    try {
      if (fs.existsSync(thumbPath)) {
        fs.unlinkSync(thumbPath)
      }
    } catch (err) {
      logger.error(`Failed to delete thumbnail ${id}`, err)
    }
  }
}

export const uploaderDataManager = new UploaderDataManager()
