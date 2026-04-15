/** Activity context for enriched apps */
export interface ActivityContext {
  project?: string // 项目名 (High level)
  file?: string // 文件名/页面标题 (Granular level)
  url?: string // 浏览器 URL
  domain?: string // 提取的域名 (github.com), 方便饼图统计
  rawTitle?: string // 原始标题作为兜底，AI 分析时可读取
}

/** Single window activity record */
export interface WindowActivityRecord {
  startTime: string // ISO 8601
  endTime: string // ISO 8601
  duration: number // seconds
  app: string // App name
  bundleId?: string // macOS bundle ID
  title?: string // Window title (optional)
  context?: ActivityContext
}

/** Daily tracker file structure */
export interface DailyTrackerData {
  date: string // YYYY-MM-DD
  version: 1
  records: WindowActivityRecord[]
  meta: {
    totalActiveTime: number // seconds
    appSummary: Record<string, number> // app -> seconds
  }
}

/** App usage summary entry */
export interface AppSummaryEntry {
  app: string
  duration: number // seconds
  percentage: number
}

/** Query result for date range */
export interface TrackerQueryResult {
  startDate: string
  endDate: string
  totalActiveTime: number
  records: WindowActivityRecord[]
  appSummary: AppSummaryEntry[]
}
