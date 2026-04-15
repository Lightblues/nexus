/// <reference types="vite/client" />

interface PomodoroSession {
  type: 'work' | 'shortBreak' | 'longBreak'
  project?: string
  tags?: string[]
  task?: string
}

interface PomodoroStatus {
  state: 'idle' | 'running' | 'paused' | 'finished'
  sessionType: 'work' | 'shortBreak' | 'longBreak'
  remainingSeconds: number
  totalSeconds: number
  completedSessions: number
  currentSession?: PomodoroSession
}

interface PomodoroStats {
  totalSessions: number
  history: unknown[]
}

interface DailyStats {
  date: string
  totalSessions: number
  totalMinutes: number
  sessions: unknown[]
}

interface WeeklyStats {
  days: DailyStats[]
  totalSessions: number
  totalMinutes: number
}

interface ActivityData {
  date: string
  count: number
  level: 0 | 1 | 2 | 3 | 4
}

interface TimelineSegment {
  startTime: string
  endTime: string
  type: 'work' | 'shortBreak' | 'longBreak'
  duration: number
  project?: string
}

interface SessionRecord {
  id: string
  startTime: string
  endTime: string
  duration: number
  type: 'work' | 'shortBreak' | 'longBreak'
  completionType: 'normal' | 'early' | 'skipped'
  project?: string
  tags?: string[]
  task?: string
}

interface SessionUpdate {
  id: string
  startTime?: string
  endTime?: string
  project?: string
  tags?: string[]
  task?: string
}

interface NextActionOption {
  action: 'startBreak' | 'startWork' | 'exit'
  label: string
  sessionType?: 'work' | 'shortBreak' | 'longBreak'
}

interface LastSessionInfo {
  project?: string
  tags?: string[]
  task?: string
}

interface TrackerConfig {
  enabled: boolean
  pollInterval: number
  idleThreshold: number
  recordTitle: boolean
  enrichApps: string[]
}

interface AppConfig {
  pomodoro: {
    workDuration: number
    shortBreakDuration: number
    longBreakDuration: number
    sessionsBeforeLongBreak: number
    projects: Array<{ name: string; color: string }>
    tags: string[]
  }
  ui: {
    windowWidth: number
    windowHeight: number
  }
  tracker: TrackerConfig
}

interface TrackerStatus {
  enabled: boolean
  running: boolean
  permissionGranted: boolean
}

interface ActivityContext {
  project?: string
  file?: string
  url?: string
  domain?: string
  rawTitle?: string
}

interface WindowActivityRecord {
  startTime: string
  endTime: string
  duration: number
  app: string
  bundleId?: string
  title?: string
  context?: ActivityContext
}

interface DailyTrackerData {
  date: string
  version: 1
  records: WindowActivityRecord[]
  meta: {
    totalActiveTime: number
    appSummary: Record<string, number>
  }
}

interface AppSummaryEntry {
  app: string
  duration: number
  percentage: number
}

interface ValidationResult {
  valid: boolean
  error?: string
}

interface WriteResult {
  success: boolean
  error?: string
}

interface UploaderConfig {
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

interface ImageMeta {
  buffer: number[]
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  width: number
  height: number
  size: number
}

interface CompressResult {
  buffer: number[]
  originalSize: number
  compressedSize: number
  width: number
  height: number
  outputFormat?: string
}

interface UploadRecord {
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

interface UploadResult {
  success: boolean
  cdnUrl?: string
  sha?: string
  error?: string
  record?: UploadRecord
}

interface WindowApi {
  pomodoro: {
    start: (session?: PomodoroSession) => Promise<PomodoroStatus>
    pause: () => Promise<PomodoroStatus>
    resume: () => Promise<PomodoroStatus>
    finishEarly: () => Promise<PomodoroStatus>
    exit: () => Promise<PomodoroStatus>
    skipBreak: () => Promise<PomodoroStatus>
    getStatus: () => Promise<PomodoroStatus>
    getNextSessionType: () => Promise<'work' | 'shortBreak' | 'longBreak'>
    getStats: () => Promise<PomodoroStats>
    getNextOptions: () => Promise<NextActionOption[]>
    updateSession: (updates: Partial<PomodoroSession>) => Promise<PomodoroStatus>
    getProjects: () => Promise<string[]>
    addProject: (project: string) => Promise<string[]>
    getTags: () => Promise<string[]>
    addTag: (tag: string) => Promise<string[]>
    getLastSession: () => Promise<LastSessionInfo>
    onTick: (callback: (seconds: number) => void) => void
    onStatus: (callback: (status: PomodoroStatus) => void) => void
    onFinished: (callback: (sessionType: string) => void) => void
  }
  config: {
    get: () => Promise<AppConfig>
    readRaw: () => Promise<string>
    validate: (content: string) => Promise<ValidationResult>
    writeRaw: (content: string) => Promise<WriteResult>
  }
  stats: {
    getToday: () => Promise<DailyStats>
    getWeekly: () => Promise<WeeklyStats>
    getActivity: (months?: number) => Promise<ActivityData[]>
    getTimeline: (date?: string) => Promise<TimelineSegment[]>
    getSessions: (date?: string) => Promise<SessionRecord[]>
    updateSession: (id: string, updates: Omit<SessionUpdate, 'id'>) => Promise<SessionRecord | null>
  }
  window: {
    openStats: () => Promise<void>
    openSettings: () => Promise<void>
  }
  tracker: {
    getStatus: () => Promise<TrackerStatus>
    getDay: (date: string) => Promise<DailyTrackerData>
    getDateRange: (startDate: string, endDate: string) => Promise<DailyTrackerData[]>
    getSummary: (startDate: string, endDate: string) => Promise<AppSummaryEntry[]>
  }
  uploader: {
    getConfig: () => Promise<UploaderConfig | null>
    getPendingImage: () => Promise<{ buffer: number[]; filename: string } | null>
    getClipboardImage: () => Promise<ImageMeta | null>
    getImageMeta: (buffer: number[]) => Promise<{ format: string; width: number; height: number }>
    compress: (buffer: number[], quality: number, format: 'auto' | 'webp' | 'jpeg' | 'png') => Promise<CompressResult>
    upload: (
      buffer: number[],
      filename: string,
      path: string,
      meta: { width: number; height: number; format: string; originalSize: number }
    ) => Promise<UploadResult>
    delete: (id: string) => Promise<{ success: boolean; error?: string }>
    getHistory: () => Promise<UploadRecord[]>
    getRecentPaths: () => Promise<string[]>
    copyUrl: (url: string) => Promise<{ success: boolean }>
    getThumbnail: (id: string) => Promise<number[] | null>
    onImageDropped: (callback: (data: { buffer: number[]; filename: string }) => void) => void
  }
}

declare global {
  interface Window {
    api: WindowApi
  }
}

export {}
