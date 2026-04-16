import { contextBridge, ipcRenderer } from 'electron'
import { IPC } from '@shared/ipc'
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
      ipcRenderer.invoke(IPC.pomodoro.start, session),
    pause: (): Promise<PomodoroStatus> => ipcRenderer.invoke(IPC.pomodoro.pause),
    resume: (): Promise<PomodoroStatus> => ipcRenderer.invoke(IPC.pomodoro.resume),
    finishEarly: (): Promise<PomodoroStatus> => ipcRenderer.invoke(IPC.pomodoro.finishEarly),
    exit: (): Promise<PomodoroStatus> => ipcRenderer.invoke(IPC.pomodoro.exit),
    skipBreak: (): Promise<PomodoroStatus> => ipcRenderer.invoke(IPC.pomodoro.skipBreak),
    getStatus: (): Promise<PomodoroStatus> => ipcRenderer.invoke(IPC.pomodoro.status),
    getNextSessionType: (): Promise<'work' | 'shortBreak' | 'longBreak'> =>
      ipcRenderer.invoke(IPC.pomodoro.nextSessionType),
    getStats: (): Promise<PomodoroStats> => ipcRenderer.invoke(IPC.pomodoro.stats),
    getNextOptions: (): Promise<NextActionOption[]> =>
      ipcRenderer.invoke(IPC.pomodoro.nextOptions),
    updateSession: (updates: Partial<PomodoroSession>): Promise<PomodoroStatus> =>
      ipcRenderer.invoke(IPC.pomodoro.updateSession, updates),
    getProjects: (): Promise<string[]> => ipcRenderer.invoke(IPC.pomodoro.getProjects),
    addProject: (project: string): Promise<string[]> =>
      ipcRenderer.invoke(IPC.pomodoro.addProject, project),
    getTags: (): Promise<string[]> => ipcRenderer.invoke(IPC.pomodoro.getTags),
    addTag: (tag: string): Promise<string[]> => ipcRenderer.invoke(IPC.pomodoro.addTag, tag),
    getLastSession: (): Promise<LastSessionInfo> =>
      ipcRenderer.invoke(IPC.pomodoro.getLastSession),
    onTick: (callback: (seconds: number) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, seconds: number) => callback(seconds)
      ipcRenderer.on(IPC.pomodoro.tick, handler)
      return () => ipcRenderer.removeListener(IPC.pomodoro.tick, handler)
    },
    onStatus: (callback: (status: PomodoroStatus) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, status: PomodoroStatus) => callback(status)
      ipcRenderer.on(IPC.pomodoro.status, handler)
      return () => ipcRenderer.removeListener(IPC.pomodoro.status, handler)
    },
    onFinished: (callback: (sessionType: string) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, sessionType: string) => callback(sessionType)
      ipcRenderer.on(IPC.pomodoro.finished, handler)
      return () => ipcRenderer.removeListener(IPC.pomodoro.finished, handler)
    }
  },
  config: {
    get: (): Promise<AppConfig> => ipcRenderer.invoke(IPC.config.get),
    readRaw: (): Promise<string> => ipcRenderer.invoke(IPC.config.readRaw),
    validate: (content: string): Promise<ValidationResult> => ipcRenderer.invoke(IPC.config.validate, content),
    writeRaw: (content: string): Promise<WriteResult> => ipcRenderer.invoke(IPC.config.writeRaw, content)
  },
  stats: {
    getToday: (): Promise<DailyStats> => ipcRenderer.invoke(IPC.stats.getToday),
    getWeekly: (): Promise<WeeklyStats> => ipcRenderer.invoke(IPC.stats.getWeekly),
    getActivity: (months?: number): Promise<ActivityData[]> =>
      ipcRenderer.invoke(IPC.stats.getActivity, months),
    getTimeline: (date?: string): Promise<TimelineSegment[]> =>
      ipcRenderer.invoke(IPC.stats.getTimeline, date),
    getSessions: (date?: string): Promise<SessionRecord[]> =>
      ipcRenderer.invoke(IPC.stats.getSessions, date),
    updateSession: (id: string, updates: Omit<SessionUpdate, 'id'>): Promise<SessionRecord | null> =>
      ipcRenderer.invoke(IPC.stats.updateSession, id, updates)
  },
  window: {
    openStats: (): Promise<void> => ipcRenderer.invoke(IPC.window.openStats),
    openSettings: (): Promise<void> => ipcRenderer.invoke(IPC.window.openSettings)
  },
  tracker: {
    getStatus: (): Promise<TrackerStatus> => ipcRenderer.invoke(IPC.tracker.getStatus),
    getDay: (date: string): Promise<DailyTrackerData> => ipcRenderer.invoke(IPC.tracker.getDay, date),
    getDateRange: (startDate: string, endDate: string): Promise<DailyTrackerData[]> =>
      ipcRenderer.invoke(IPC.tracker.getDateRange, startDate, endDate),
    getSummary: (startDate: string, endDate: string): Promise<AppSummaryEntry[]> =>
      ipcRenderer.invoke(IPC.tracker.getSummary, startDate, endDate)
  },
  uploader: {
    getConfig: (): Promise<UploaderConfig | null> => ipcRenderer.invoke(IPC.uploader.getConfig),
    getPendingImage: (): Promise<{ buffer: number[]; filename: string } | null> =>
      ipcRenderer.invoke(IPC.uploader.getPendingImage),
    getClipboardImage: (): Promise<ImageMeta | null> => ipcRenderer.invoke(IPC.uploader.getClipboardImage),
    getImageMeta: (buffer: number[]): Promise<{ format: string; width: number; height: number }> =>
      ipcRenderer.invoke(IPC.uploader.getImageMeta, buffer),
    compress: (buffer: number[], quality: number, format: 'auto' | 'webp' | 'jpeg' | 'png'): Promise<CompressResult> =>
      ipcRenderer.invoke(IPC.uploader.compress, buffer, quality, format),
    upload: (
      buffer: number[],
      filename: string,
      path: string,
      meta: { width: number; height: number; format: string; originalSize: number }
    ): Promise<UploadResult> => ipcRenderer.invoke(IPC.uploader.upload, buffer, filename, path, meta),
    delete: (id: string): Promise<{ success: boolean; error?: string }> =>
      ipcRenderer.invoke(IPC.uploader.delete, id),
    getHistory: (): Promise<UploadRecord[]> => ipcRenderer.invoke(IPC.uploader.getHistory),
    getRecentPaths: (): Promise<string[]> => ipcRenderer.invoke(IPC.uploader.getRecentPaths),
    copyUrl: (url: string): Promise<{ success: boolean }> => ipcRenderer.invoke(IPC.uploader.copyUrl, url),
    getThumbnail: (id: string): Promise<number[] | null> => ipcRenderer.invoke(IPC.uploader.getThumbnail, id),
    onImageDropped: (callback: (data: { buffer: number[]; filename: string }) => void): (() => void) => {
      const handler = (_event: Electron.IpcRendererEvent, data: { buffer: number[]; filename: string }) => callback(data)
      ipcRenderer.on(IPC.uploader.imageDropped, handler)
      return () => ipcRenderer.removeListener(IPC.uploader.imageDropped, handler)
    }
  }
}

contextBridge.exposeInMainWorld('api', api)
