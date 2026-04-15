import * as fs from 'fs'
import * as path from 'path'
import { pathManager } from '../../core/PathManager'
import { logger } from '../../core/Logger'
import type { DailyTrackerData, WindowActivityRecord, AppSummaryEntry } from './types'

const FLUSH_INTERVAL = 5 * 60 * 1000 // 5 minutes
const MAX_BUFFER_SIZE = 100

class TrackerDataManager {
  private trackerDir: string
  private buffer: WindowActivityRecord[] = []
  private currentDate: string = ''
  private flushTimer: NodeJS.Timeout | null = null

  constructor() {
    this.trackerDir = path.join(pathManager.eaDir, 'tracker')
  }

  init(): void {
    fs.mkdirSync(this.trackerDir, { recursive: true })
    this.currentDate = this.getTodayDate()
    logger.info('TrackerDataManager initialized', { dir: this.trackerDir })
  }

  private getTodayDate(): string {
    return new Date().toISOString().slice(0, 10)
  }

  private getFilePath(date: string): string {
    return path.join(this.trackerDir, `${date}.json`)
  }

  private loadDailyData(date: string): DailyTrackerData {
    const filePath = this.getFilePath(date)
    if (fs.existsSync(filePath)) {
      try {
        const content = fs.readFileSync(filePath, 'utf-8')
        return JSON.parse(content) as DailyTrackerData
      } catch (err) {
        logger.error('Failed to load tracker data', { date, error: err })
      }
    }
    return this.createEmptyDailyData(date)
  }

  private createEmptyDailyData(date: string): DailyTrackerData {
    return {
      date,
      version: 1,
      records: [],
      meta: { totalActiveTime: 0, appSummary: {} }
    }
  }

  private saveDailyData(data: DailyTrackerData): void {
    const filePath = this.getFilePath(data.date)
    try {
      fs.writeFileSync(filePath, JSON.stringify(data, null, 2))
    } catch (err) {
      logger.error('Failed to save tracker data', { date: data.date, error: err })
    }
  }

  /** Add a record to buffer, returns true if date changed */
  addRecord(record: WindowActivityRecord): boolean {
    const recordDate = record.startTime.slice(0, 10)
    const dateChanged = recordDate !== this.currentDate

    if (dateChanged) {
      this.flush() // Flush old day's data
      this.currentDate = recordDate
    }

    this.buffer.push(record)

    if (this.buffer.length >= MAX_BUFFER_SIZE) {
      this.flush()
    }

    return dateChanged
  }

  /** Update the last record's endTime (for merging) */
  updateLastRecordEndTime(endTime: string): void {
    if (this.buffer.length > 0) {
      const last = this.buffer[this.buffer.length - 1]
      last.endTime = endTime
      last.duration = Math.round((new Date(endTime).getTime() - new Date(last.startTime).getTime()) / 1000)
    }
  }

  /** Get the last record in buffer */
  getLastRecord(): WindowActivityRecord | null {
    return this.buffer.length > 0 ? this.buffer[this.buffer.length - 1] : null
  }

  /** Flush buffer to disk */
  flush(): void {
    if (this.buffer.length === 0) return

    const byDate = new Map<string, WindowActivityRecord[]>()
    for (const record of this.buffer) {
      const date = record.startTime.slice(0, 10)
      if (!byDate.has(date)) byDate.set(date, [])
      byDate.get(date)!.push(record)
    }

    for (const [date, records] of byDate) {
      const data = this.loadDailyData(date)
      data.records.push(...records)
      this.updateMeta(data)
      this.saveDailyData(data)
      logger.debug('Flushed tracker records', { date, count: records.length })
    }

    this.buffer = []
  }

  private updateMeta(data: DailyTrackerData): void {
    let total = 0
    const summary: Record<string, number> = {}

    for (const record of data.records) {
      total += record.duration
      summary[record.app] = (summary[record.app] || 0) + record.duration
    }

    data.meta.totalActiveTime = total
    data.meta.appSummary = summary
  }

  /** Start periodic flush timer */
  startAutoFlush(): void {
    if (this.flushTimer) return
    this.flushTimer = setInterval(() => this.flush(), FLUSH_INTERVAL)
    logger.debug('Auto-flush started')
  }

  /** Stop periodic flush timer */
  stopAutoFlush(): void {
    if (this.flushTimer) {
      clearInterval(this.flushTimer)
      this.flushTimer = null
    }
  }

  /** Query records for a specific date */
  getDay(date: string): DailyTrackerData {
    // First flush any buffered data for accurate results
    if (date === this.currentDate && this.buffer.length > 0) {
      this.flush()
    }
    return this.loadDailyData(date)
  }

  /** Query records for a date range */
  getDateRange(startDate: string, endDate: string): DailyTrackerData[] {
    this.flush() // Ensure all data is persisted

    const results: DailyTrackerData[] = []
    const start = new Date(startDate)
    const end = new Date(endDate)

    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      const dateStr = d.toISOString().slice(0, 10)
      const filePath = this.getFilePath(dateStr)
      if (fs.existsSync(filePath)) {
        results.push(this.loadDailyData(dateStr))
      }
    }

    return results
  }

  /** Get app summary for a date range */
  getAppSummary(startDate: string, endDate: string): AppSummaryEntry[] {
    const days = this.getDateRange(startDate, endDate)
    const combined: Record<string, number> = {}
    let total = 0

    for (const day of days) {
      for (const [app, duration] of Object.entries(day.meta.appSummary)) {
        combined[app] = (combined[app] || 0) + duration
        total += duration
      }
    }

    return Object.entries(combined)
      .map(([app, duration]) => ({
        app,
        duration,
        percentage: total > 0 ? Math.round((duration / total) * 100) : 0
      }))
      .sort((a, b) => b.duration - a.duration)
  }

  /** Cleanup on shutdown */
  shutdown(): void {
    this.stopAutoFlush()
    this.flush()
    logger.info('TrackerDataManager shutdown')
  }
}

export const trackerDataManager = new TrackerDataManager()
