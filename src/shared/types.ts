// ============================================================
// Shared types used across main, preload, and renderer processes
// ============================================================

// --- Pomodoro ---

export type TimerState = 'idle' | 'running' | 'paused' | 'finished'
export type SessionType = 'work' | 'shortBreak' | 'longBreak'

export interface PomodoroSession {
  type: SessionType
  project?: string
  tags?: string[]
  task?: string
}

export interface PomodoroStatus {
  state: TimerState
  sessionType: SessionType
  remainingSeconds: number
  totalSeconds: number
  completedSessions: number
  currentSession?: PomodoroSession
}

export interface SessionRecord {
  id: string
  startTime: string
  endTime: string
  duration: number // actual minutes
  type: SessionType
  completionType: 'normal' | 'early' | 'skipped'
  project?: string
  tags?: string[]
  task?: string
}

export interface SessionUpdate {
  id: string
  startTime?: string
  endTime?: string
  project?: string
  tags?: string[]
  task?: string
}

export interface NextActionOption {
  action: 'startBreak' | 'startWork' | 'exit'
  label: string
  sessionType?: SessionType
}

export interface LastSessionInfo {
  project?: string
  tags?: string[]
  task?: string
}

export interface PomodoroStats {
  totalSessions: number
  history: SessionRecord[]
}

export interface PomodoroMetadata {
  projects: string[]
  tags: string[]
  lastSession: LastSessionInfo
}

// --- Stats ---

export interface DailyStats {
  date: string
  totalSessions: number
  totalMinutes: number
  sessions: SessionRecord[]
}

export interface WeeklyStats {
  days: DailyStats[]
  totalSessions: number
  totalMinutes: number
}

export interface ActivityData {
  date: string
  count: number
  level: 0 | 1 | 2 | 3 | 4
}

export interface TimelineSegment {
  startTime: string
  endTime: string
  type: SessionType
  duration: number
  project?: string
}

// --- Config ---

export interface PomodoroConfig {
  workDuration: number
  shortBreakDuration: number
  longBreakDuration: number
  sessionsBeforeLongBreak: number
  projects: Array<{ name: string; color: string }>
  tags: string[]
  showPopoverOnComplete: boolean
}

export interface UIConfig {
  windowWidth: number
  windowHeight: number
}

export interface TrackerConfig {
  enabled: boolean
  pollInterval: number // seconds
  idleThreshold: number // seconds
  recordTitle: boolean
  enrichApps: string[]
}

export interface UploaderConfig {
  enabled: boolean
  github: {
    token: string
    owner: string
    repo: string
    branch: string
  }
  cdn: {
    baseUrl: string
  }
  compress: {
    quality: number
    defaultFormat: 'auto' | 'webp' | 'jpeg' | 'png'
  }
  defaultPath: string
  cacheThumbnails: boolean
}

export interface AppConfig {
  pomodoro: PomodoroConfig
  ui: UIConfig
  tracker: TrackerConfig
  uploader: UploaderConfig
}

// --- Tracker ---

export interface ActivityContext {
  project?: string
  file?: string
  url?: string
  domain?: string
  rawTitle?: string
}

export interface WindowActivityRecord {
  startTime: string
  endTime: string
  duration: number // seconds
  app: string
  bundleId?: string
  title?: string
  context?: ActivityContext
}

export interface DailyTrackerData {
  date: string
  version: 1
  records: WindowActivityRecord[]
  meta: {
    totalActiveTime: number
    appSummary: Record<string, number>
  }
}

export interface AppSummaryEntry {
  app: string
  duration: number
  percentage: number
}

export interface TrackerStatus {
  enabled: boolean
  running: boolean
  permissionGranted: boolean
}

export interface TrackerQueryResult {
  startDate: string
  endDate: string
  totalActiveTime: number
  records: WindowActivityRecord[]
  appSummary: AppSummaryEntry[]
}

// --- Uploader ---

export interface UploadRecord {
  id: string
  filename: string
  originalName: string
  timestamp: string
  originalSize: number
  compressedSize: number
  width: number
  height: number
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  path: string
  cdnUrl: string
  sha: string
}

export interface UploaderData {
  version: 1
  recentPaths: string[]
  history: UploadRecord[]
}

/** ImageMeta used in IPC (buffer as number[] for serialization) */
export interface ImageMeta {
  buffer: number[]
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  width: number
  height: number
  size: number
}

/** CompressResult used in IPC (buffer as number[] for serialization) */
export interface CompressResult {
  buffer: number[]
  originalSize: number
  compressedSize: number
  width: number
  height: number
  outputFormat?: string
}

export interface UploadResult {
  success: boolean
  cdnUrl?: string
  sha?: string
  error?: string
  record?: UploadRecord
}

// --- Settings ---

export interface ValidationResult {
  valid: boolean
  error?: string
}

export interface WriteResult {
  success: boolean
  error?: string
}

// --- Data ---

export interface AppData {
  stats: {
    pomodoro: PomodoroStats
  }
  metadata: {
    pomodoro: PomodoroMetadata
  }
}
