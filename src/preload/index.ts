import { contextBridge, ipcRenderer } from 'electron'

export interface PomodoroSession {
  type: 'work' | 'shortBreak' | 'longBreak'
  project?: string
  tags?: string[]
  task?: string
}

export interface PomodoroStatus {
  state: 'idle' | 'running' | 'paused' | 'finished'
  sessionType: 'work' | 'shortBreak' | 'longBreak'
  remainingSeconds: number
  totalSeconds: number
  completedSessions: number
  currentSession?: PomodoroSession
}

export interface PomodoroStats {
  totalSessions: number
  history: unknown[]
}

export interface DailyStats {
  date: string
  totalSessions: number
  totalMinutes: number
  sessions: unknown[]
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
  type: 'work' | 'shortBreak' | 'longBreak'
  duration: number
  project?: string
}

export interface SessionRecord {
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
  sessionType?: 'work' | 'shortBreak' | 'longBreak'
}

export interface LastSessionInfo {
  project?: string
  tags?: string[]
}

export interface TrackerConfig {
  enabled: boolean
  pollInterval: number
  idleThreshold: number
  recordTitle: boolean
  enrichApps: string[]
}

export interface AppConfig {
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

export interface TrackerStatus {
  enabled: boolean
  running: boolean
  permissionGranted: boolean
}

export interface ActivityContext {
  project?: string // 项目名 (High level)
  file?: string // 文件名/页面标题 (Granular level)
  url?: string // 浏览器 URL
  domain?: string // 提取的域名 (github.com)
  rawTitle?: string // 原始标题作为兜底
}

export interface WindowActivityRecord {
  startTime: string
  endTime: string
  duration: number
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

export interface ValidationResult {
  valid: boolean
  error?: string
}

export interface WriteResult {
  success: boolean
  error?: string
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

export interface ImageMeta {
  buffer: number[]
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  width: number
  height: number
  size: number
}

export interface CompressResult {
  buffer: number[]
  originalSize: number
  compressedSize: number
  width: number
  height: number
  outputFormat?: string
}

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

export interface UploadResult {
  success: boolean
  cdnUrl?: string
  sha?: string
  error?: string
  record?: UploadRecord
}

const api = {
  pomodoro: {
    start: (session?: PomodoroSession): Promise<PomodoroStatus> =>
      ipcRenderer.invoke('pomodoro:start', session),
    pause: (): Promise<PomodoroStatus> => ipcRenderer.invoke('pomodoro:pause'),
    resume: (): Promise<PomodoroStatus> => ipcRenderer.invoke('pomodoro:resume'),
    finishEarly: (): Promise<PomodoroStatus> => ipcRenderer.invoke('pomodoro:finish-early'),
    exit: (): Promise<PomodoroStatus> => ipcRenderer.invoke('pomodoro:exit'),
    skipBreak: (): Promise<PomodoroStatus> => ipcRenderer.invoke('pomodoro:skip-break'),
    getStatus: (): Promise<PomodoroStatus> => ipcRenderer.invoke('pomodoro:status'),
    getNextSessionType: (): Promise<'work' | 'shortBreak' | 'longBreak'> =>
      ipcRenderer.invoke('pomodoro:next-session-type'),
    getStats: (): Promise<PomodoroStats> => ipcRenderer.invoke('pomodoro:stats'),
    getNextOptions: (): Promise<NextActionOption[]> =>
      ipcRenderer.invoke('pomodoro:next-options'),
    updateSession: (updates: Partial<PomodoroSession>): Promise<PomodoroStatus> =>
      ipcRenderer.invoke('pomodoro:update-session', updates),
    getProjects: (): Promise<string[]> => ipcRenderer.invoke('pomodoro:get-projects'),
    addProject: (project: string): Promise<string[]> =>
      ipcRenderer.invoke('pomodoro:add-project', project),
    getTags: (): Promise<string[]> => ipcRenderer.invoke('pomodoro:get-tags'),
    addTag: (tag: string): Promise<string[]> => ipcRenderer.invoke('pomodoro:add-tag', tag),
    getLastSession: (): Promise<LastSessionInfo> =>
      ipcRenderer.invoke('pomodoro:get-last-session'),
    onTick: (callback: (seconds: number) => void) => {
      ipcRenderer.on('pomodoro:tick', (_event, seconds) => callback(seconds))
    },
    onStatus: (callback: (status: PomodoroStatus) => void) => {
      ipcRenderer.on('pomodoro:status', (_event, status) => callback(status))
    },
    onFinished: (callback: (sessionType: string) => void) => {
      ipcRenderer.on('pomodoro:finished', (_event, sessionType) => callback(sessionType))
    }
  },
  config: {
    get: (): Promise<AppConfig> => ipcRenderer.invoke('config:get'),
    readRaw: (): Promise<string> => ipcRenderer.invoke('config:read-raw'),
    validate: (content: string): Promise<ValidationResult> => ipcRenderer.invoke('config:validate', content),
    writeRaw: (content: string): Promise<WriteResult> => ipcRenderer.invoke('config:write-raw', content)
  },
  stats: {
    getToday: (): Promise<DailyStats> => ipcRenderer.invoke('stats:get-today'),
    getWeekly: (): Promise<WeeklyStats> => ipcRenderer.invoke('stats:get-weekly'),
    getActivity: (months?: number): Promise<ActivityData[]> =>
      ipcRenderer.invoke('stats:get-activity', months),
    getTimeline: (date?: string): Promise<TimelineSegment[]> =>
      ipcRenderer.invoke('stats:get-timeline', date),
    getSessions: (date?: string): Promise<SessionRecord[]> =>
      ipcRenderer.invoke('stats:get-sessions', date),
    updateSession: (id: string, updates: Omit<SessionUpdate, 'id'>): Promise<SessionRecord | null> =>
      ipcRenderer.invoke('stats:update-session', id, updates)
  },
  window: {
    openStats: (): Promise<void> => ipcRenderer.invoke('window:open-stats'),
    openSettings: (): Promise<void> => ipcRenderer.invoke('window:open-settings')
  },
  tracker: {
    getStatus: (): Promise<TrackerStatus> => ipcRenderer.invoke('tracker:get-status'),
    getDay: (date: string): Promise<DailyTrackerData> => ipcRenderer.invoke('tracker:get-day', date),
    getDateRange: (startDate: string, endDate: string): Promise<DailyTrackerData[]> =>
      ipcRenderer.invoke('tracker:get-date-range', startDate, endDate),
    getSummary: (startDate: string, endDate: string): Promise<AppSummaryEntry[]> =>
      ipcRenderer.invoke('tracker:get-summary', startDate, endDate)
  },
  uploader: {
    getConfig: (): Promise<UploaderConfig | null> => ipcRenderer.invoke('uploader:get-config'),
    getPendingImage: (): Promise<{ buffer: number[]; filename: string } | null> =>
      ipcRenderer.invoke('uploader:get-pending-image'),
    getClipboardImage: (): Promise<ImageMeta | null> => ipcRenderer.invoke('uploader:get-clipboard-image'),
    getImageMeta: (buffer: number[]): Promise<{ format: string; width: number; height: number }> =>
      ipcRenderer.invoke('uploader:get-image-meta', buffer),
    compress: (buffer: number[], quality: number, format: 'auto' | 'webp' | 'jpeg' | 'png'): Promise<CompressResult> =>
      ipcRenderer.invoke('uploader:compress', buffer, quality, format),
    upload: (
      buffer: number[],
      filename: string,
      path: string,
      meta: { width: number; height: number; format: string; originalSize: number }
    ): Promise<UploadResult> => ipcRenderer.invoke('uploader:upload', buffer, filename, path, meta),
    delete: (id: string): Promise<{ success: boolean; error?: string }> =>
      ipcRenderer.invoke('uploader:delete', id),
    getHistory: (): Promise<UploadRecord[]> => ipcRenderer.invoke('uploader:get-history'),
    getRecentPaths: (): Promise<string[]> => ipcRenderer.invoke('uploader:get-recent-paths'),
    copyUrl: (url: string): Promise<{ success: boolean }> => ipcRenderer.invoke('uploader:copy-url', url),
    getThumbnail: (id: string): Promise<number[] | null> => ipcRenderer.invoke('uploader:get-thumbnail', id),
    onImageDropped: (callback: (data: { buffer: number[]; filename: string }) => void) => {
      ipcRenderer.on('uploader:image-dropped', (_event, data) => callback(data))
    }
  }
}

contextBridge.exposeInMainWorld('api', api)

declare global {
  interface Window {
    api: typeof api
  }
}
