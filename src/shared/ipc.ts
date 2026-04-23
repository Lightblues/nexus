/** Centralized IPC channel names — single source of truth for main, preload, and renderer */

export const IPC = {
  pomodoro: {
    start: 'pomodoro:start',
    pause: 'pomodoro:pause',
    resume: 'pomodoro:resume',
    finishEarly: 'pomodoro:finish-early',
    exit: 'pomodoro:exit',
    skipBreak: 'pomodoro:skip-break',
    status: 'pomodoro:status',
    nextSessionType: 'pomodoro:next-session-type',
    stats: 'pomodoro:stats',
    nextOptions: 'pomodoro:next-options',
    updateSession: 'pomodoro:update-session',
    getProjects: 'pomodoro:get-projects',
    addProject: 'pomodoro:add-project',
    getTags: 'pomodoro:get-tags',
    addTag: 'pomodoro:add-tag',
    getLastSession: 'pomodoro:get-last-session',
    // Events (main → renderer)
    tick: 'pomodoro:tick',
    finished: 'pomodoro:finished',
  },
  stats: {
    getToday: 'stats:get-today',
    getWeekly: 'stats:get-weekly',
    getActivity: 'stats:get-activity',
    getTimeline: 'stats:get-timeline',
    getSessions: 'stats:get-sessions',
    updateSession: 'stats:update-session',
  },
  config: {
    get: 'config:get',
    readRaw: 'config:read-raw',
    validate: 'config:validate',
    writeRaw: 'config:write-raw',
  },
  window: {
    openStats: 'window:open-stats',
    openSettings: 'window:open-settings',
  },
  palette: {
    list: 'palette:list',
    execute: 'palette:execute',
    close: 'palette:close',
    // Events (main → renderer)
    opened: 'palette:opened',
  },
  tracker: {
    getStatus: 'tracker:get-status',
    getDay: 'tracker:get-day',
    getDateRange: 'tracker:get-date-range',
    getSummary: 'tracker:get-summary',
  },
  uploader: {
    getConfig: 'uploader:get-config',
    getPendingImage: 'uploader:get-pending-image',
    getClipboardImage: 'uploader:get-clipboard-image',
    getImageMeta: 'uploader:get-image-meta',
    compress: 'uploader:compress',
    upload: 'uploader:upload',
    delete: 'uploader:delete',
    getHistory: 'uploader:get-history',
    getRecentPaths: 'uploader:get-recent-paths',
    copyUrl: 'uploader:copy-url',
    getThumbnail: 'uploader:get-thumbnail',
    // Events (main → renderer)
    imageDropped: 'uploader:image-dropped',
  },
} as const
