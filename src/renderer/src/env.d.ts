/// <reference types="vite/client" />

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
    onTick: (callback: (seconds: number) => void) => () => void
    onStatus: (callback: (status: PomodoroStatus) => void) => () => void
    onFinished: (callback: (sessionType: string) => void) => () => void
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
    onImageDropped: (callback: (data: { buffer: number[]; filename: string }) => void) => () => void
  }
}

declare global {
  interface Window {
    api: WindowApi
  }
}

export {}
