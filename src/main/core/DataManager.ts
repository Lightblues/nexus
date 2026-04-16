import * as fs from 'fs'
import * as path from 'path'
import Store from 'electron-store'
import { pathManager } from './PathManager'
import { logger } from './Logger'
import type { SessionRecord, PomodoroStats, LastSessionInfo, PomodoroMetadata, AppData } from '@shared/types'

export type { SessionRecord, PomodoroStats, LastSessionInfo, PomodoroMetadata, AppData }

/** Days to keep in active store before archiving */
const ARCHIVE_THRESHOLD_DAYS = 90

const DEFAULT_DATA: AppData = {
  stats: {
    pomodoro: {
      totalSessions: 0,
      history: []
    }
  },
  metadata: {
    pomodoro: {
      projects: [],
      tags: [],
      lastSession: {}
    }
  }
}

class DataManager {
  private store: Store<AppData> | null = null

  init(): void {
    this.store = new Store<AppData>({
      name: 'data',
      cwd: pathManager.eaDir,
      defaults: DEFAULT_DATA
    })
    logger.info('DataManager initialized', { path: pathManager.dataPath })
    this.archiveOldSessions()
  }

  get<K extends keyof AppData>(key: K): AppData[K] {
    if (!this.store) throw new Error('DataManager not initialized')
    return this.store.get(key)
  }

  set<K extends keyof AppData>(key: K, value: AppData[K]): void {
    if (!this.store) throw new Error('DataManager not initialized')
    this.store.set(key, value)
  }

  addSession(session: SessionRecord): void {
    const stats = this.get('stats')
    stats.pomodoro.history.push(session)
    if (session.type === 'work' && session.completionType !== 'skipped') {
      stats.pomodoro.totalSessions++
    }
    this.set('stats', stats)
    // Update metadata for work sessions
    if (session.type === 'work') {
      this.updateMetadataFromSession(session)
    }
    logger.info('Session recorded', { id: session.id, type: session.type })
  }

  private updateMetadataFromSession(session: SessionRecord): void {
    const metadata = this.get('metadata')
    if (session.project && !metadata.pomodoro.projects.includes(session.project)) {
      metadata.pomodoro.projects.push(session.project)
    }
    if (session.tags) {
      for (const tag of session.tags) {
        if (!metadata.pomodoro.tags.includes(tag)) {
          metadata.pomodoro.tags.push(tag)
        }
      }
    }
    metadata.pomodoro.lastSession = {
      project: session.project,
      tags: session.tags
    }
    this.set('metadata', metadata)
  }

  getStats(): PomodoroStats {
    return this.get('stats').pomodoro
  }

  /** Get all sessions including archived ones (for stats views that need full history) */
  getAllSessions(): SessionRecord[] {
    const active = this.get('stats').pomodoro.history
    const archived = this.loadAllArchived()
    return [...archived, ...active]
  }

  getProjects(): string[] {
    return this.get('metadata').pomodoro.projects
  }

  addProject(project: string): void {
    const metadata = this.get('metadata')
    if (!metadata.pomodoro.projects.includes(project)) {
      metadata.pomodoro.projects.push(project)
      this.set('metadata', metadata)
    }
  }

  getTags(): string[] {
    return this.get('metadata').pomodoro.tags
  }

  addTag(tag: string): void {
    const metadata = this.get('metadata')
    if (!metadata.pomodoro.tags.includes(tag)) {
      metadata.pomodoro.tags.push(tag)
      this.set('metadata', metadata)
    }
  }

  getLastSession(): LastSessionInfo {
    return this.get('metadata').pomodoro.lastSession
  }

  updateSession(id: string, updates: Partial<Pick<SessionRecord, 'startTime' | 'endTime' | 'project' | 'tags' | 'task'>>): SessionRecord | null {
    const stats = this.get('stats')
    const index = stats.pomodoro.history.findIndex((s) => s.id === id)
    if (index === -1) return null

    const session = stats.pomodoro.history[index]
    if (updates.startTime !== undefined) session.startTime = updates.startTime
    if (updates.endTime !== undefined) session.endTime = updates.endTime
    if (updates.project !== undefined) session.project = updates.project
    if (updates.tags !== undefined) session.tags = updates.tags
    if (updates.task !== undefined) session.task = updates.task

    if (updates.startTime !== undefined || updates.endTime !== undefined) {
      const start = new Date(session.startTime).getTime()
      const end = new Date(session.endTime).getTime()
      session.duration = Math.round((end - start) / 60000)
    }

    stats.pomodoro.history[index] = session
    this.set('stats', stats)

    if (updates.project || updates.tags) {
      this.updateMetadataFromSession(session)
    }

    logger.info('Session updated', { id: session.id })
    return session
  }

  // --- Archiving ---

  /** Move sessions older than ARCHIVE_THRESHOLD_DAYS to yearly archive files */
  private archiveOldSessions(): void {
    const stats = this.get('stats')
    const history = stats.pomodoro.history
    if (history.length === 0) return

    const cutoff = new Date()
    cutoff.setDate(cutoff.getDate() - ARCHIVE_THRESHOLD_DAYS)
    const cutoffStr = cutoff.toISOString()

    const toArchive = history.filter((s) => s.startTime < cutoffStr)
    if (toArchive.length === 0) return

    // Group by year
    const byYear = new Map<string, SessionRecord[]>()
    for (const session of toArchive) {
      const year = session.startTime.substring(0, 4) // "2025"
      const existing = byYear.get(year) || []
      existing.push(session)
      byYear.set(year, existing)
    }

    // Write to archive files (merge with existing)
    for (const [year, sessions] of byYear) {
      this.appendToArchive(year, sessions)
    }

    // Remove archived from active store
    const remaining = history.filter((s) => s.startTime >= cutoffStr)
    stats.pomodoro.history = remaining
    this.set('stats', stats)

    logger.info(`Archived ${toArchive.length} sessions, ${remaining.length} remaining in active store`)
  }

  private getArchivePath(year: string): string {
    return path.join(pathManager.archiveDir, `pomodoro-${year}.json`)
  }

  private appendToArchive(year: string, sessions: SessionRecord[]): void {
    const archivePath = this.getArchivePath(year)
    let existing: SessionRecord[] = []

    try {
      if (fs.existsSync(archivePath)) {
        const content = fs.readFileSync(archivePath, 'utf-8')
        existing = JSON.parse(content)
      }
    } catch (err) {
      logger.error(`Failed to read archive ${year}`, err)
    }

    // Deduplicate by id
    const existingIds = new Set(existing.map((s) => s.id))
    const newSessions = sessions.filter((s) => !existingIds.has(s.id))
    const merged = [...existing, ...newSessions].sort(
      (a, b) => a.startTime.localeCompare(b.startTime)
    )

    try {
      fs.writeFileSync(archivePath, JSON.stringify(merged, null, 2))
      logger.info(`Archive ${year}: ${newSessions.length} new, ${merged.length} total`)
    } catch (err) {
      logger.error(`Failed to write archive ${year}`, err)
    }
  }

  private loadAllArchived(): SessionRecord[] {
    const archiveDir = pathManager.archiveDir
    try {
      if (!fs.existsSync(archiveDir)) return []
      const files = fs.readdirSync(archiveDir).filter((f) => f.startsWith('pomodoro-') && f.endsWith('.json'))
      const all: SessionRecord[] = []
      for (const file of files) {
        try {
          const content = fs.readFileSync(path.join(archiveDir, file), 'utf-8')
          const sessions: SessionRecord[] = JSON.parse(content)
          all.push(...sessions)
        } catch (err) {
          logger.error(`Failed to read archive file ${file}`, err)
        }
      }
      return all.sort((a, b) => a.startTime.localeCompare(b.startTime))
    } catch {
      return []
    }
  }
}

export const dataManager = new DataManager()
