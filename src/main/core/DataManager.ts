import Store from 'electron-store'
import { pathManager } from './PathManager'
import { logger } from './Logger'

export interface SessionRecord {
  id: string
  startTime: string
  endTime: string
  duration: number // actual minutes
  type: 'work' | 'shortBreak' | 'longBreak'
  completionType: 'normal' | 'early' | 'skipped'
  project?: string
  tags?: string[]
  task?: string
}

export interface PomodoroStats {
  totalSessions: number
  history: SessionRecord[]
}

export interface LastSessionInfo {
  project?: string
  tags?: string[]
}

export interface PomodoroMetadata {
  projects: string[]
  tags: string[]
  lastSession: LastSessionInfo
}

export interface AppData {
  stats: {
    pomodoro: PomodoroStats
  }
  metadata: {
    pomodoro: PomodoroMetadata
  }
}

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
    // Add project if new
    if (session.project && !metadata.pomodoro.projects.includes(session.project)) {
      metadata.pomodoro.projects.push(session.project)
    }
    // Add tags if new
    if (session.tags) {
      for (const tag of session.tags) {
        if (!metadata.pomodoro.tags.includes(tag)) {
          metadata.pomodoro.tags.push(tag)
        }
      }
    }
    // Update lastSession
    metadata.pomodoro.lastSession = {
      project: session.project,
      tags: session.tags
    }
    this.set('metadata', metadata)
  }

  getStats(): PomodoroStats {
    return this.get('stats').pomodoro
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
    // Apply updates
    if (updates.startTime !== undefined) session.startTime = updates.startTime
    if (updates.endTime !== undefined) session.endTime = updates.endTime
    if (updates.project !== undefined) session.project = updates.project
    if (updates.tags !== undefined) session.tags = updates.tags
    if (updates.task !== undefined) session.task = updates.task

    // Recalculate duration if times changed
    if (updates.startTime !== undefined || updates.endTime !== undefined) {
      const start = new Date(session.startTime).getTime()
      const end = new Date(session.endTime).getTime()
      session.duration = Math.round((end - start) / 60000)
    }

    stats.pomodoro.history[index] = session
    this.set('stats', stats)

    // Update metadata if new project/tags
    if (updates.project || updates.tags) {
      this.updateMetadataFromSession(session)
    }

    logger.info('Session updated', { id: session.id })
    return session
  }
}

export const dataManager = new DataManager()
