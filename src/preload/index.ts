import { contextBridge, ipcRenderer } from 'electron'
import type {
  PomodoroSession,
  PomodoroStatus,
  PomodoroStats,
  DailyStats,
  WeeklyStats,
  ActivityData,
  TimelineSegment,
  SessionRecord,
  SessionUpdate,
  NextActionOption,
  LastSessionInfo,
  AppConfig,
  TrackerStatus,
  DailyTrackerData,
  AppSummaryEntry,
  ValidationResult,
  WriteResult,
  UploaderConfig,
  ImageMeta,
  CompressResult,
  UploadRecord,
  UploadResult
} from '@shared/types'

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
    onTick: (callback: (seconds: number) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, seconds: number) => callback(seconds)
      ipcRenderer.on('pomodoro:tick', handler)
      return () => ipcRenderer.removeListener('pomodoro:tick', handler)
    },
    onStatus: (callback: (status: PomodoroStatus) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, status: PomodoroStatus) => callback(status)
      ipcRenderer.on('pomodoro:status', handler)
      return () => ipcRenderer.removeListener('pomodoro:status', handler)
    },
    onFinished: (callback: (sessionType: string) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, sessionType: string) => callback(sessionType)
      ipcRenderer.on('pomodoro:finished', handler)
      return () => ipcRenderer.removeListener('pomodoro:finished', handler)
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
    onImageDropped: (callback: (data: { buffer: number[]; filename: string }) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, data: { buffer: number[]; filename: string }) => callback(data)
      ipcRenderer.on('uploader:image-dropped', handler)
      return () => ipcRenderer.removeListener('uploader:image-dropped', handler)
    }
  }
}

contextBridge.exposeInMainWorld('api', api)
