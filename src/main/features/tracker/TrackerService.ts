import { powerMonitor } from 'electron'
import { execFile } from 'child_process'
import { promisify } from 'util'
import { configManager, type TrackerConfig } from '../../core/ConfigManager'
import { logger } from '../../core/Logger'
import { permissionManager } from '../../core/PermissionManager'
import { trackerDataManager } from './TrackerDataManager'
import type { WindowActivityRecord, ActivityContext } from './types'

const execFileAsync = promisify(execFile)

interface WindowInfo {
  app: string
  title?: string
  bundleId?: string
}

/** Map bundleId to friendly display name (for Electron-based apps that show "Electron" as process name) */
const BUNDLE_TO_APP_NAME: Record<string, string> = {
  'com.microsoft.VSCode': 'Code',
  'com.microsoft.VSCodeInsiders': 'Code - Insiders',
  'com.todesktop.230313mzl4w4u92': 'Cursor'
}

/** BundleIds that should have context enrichment */
const ENRICH_BUNDLE_IDS = new Set([
  'com.microsoft.VSCode',
  'com.microsoft.VSCodeInsiders',
  'com.todesktop.230313mzl4w4u92', // Cursor
  'com.google.Chrome',
  'com.google.Chrome.beta',
  'com.apple.Safari',
  'company.thebrowser.Browser' // Arc
])

/** Get active window using AppleScript (no external binary needed) */
async function getActiveWindowAppleScript(): Promise<WindowInfo | undefined> {
  const script = `
    tell application "System Events"
      set frontApp to first application process whose frontmost is true
      set appName to name of frontApp
      set bundleId to bundle identifier of frontApp
      try
        set winTitle to name of front window of frontApp
      on error
        set winTitle to ""
      end try
      return appName & "|||" & bundleId & "|||" & winTitle
    end tell
  `
  try {
    const { stdout } = await execFileAsync('osascript', ['-e', script], { timeout: 3000 })
    const parts = stdout.trim().split('|||')
    if (parts.length >= 2) {
      const bundleId = parts[1] || undefined
      // Use friendly name if available, otherwise use process name
      const app = (bundleId && BUNDLE_TO_APP_NAME[bundleId]) || parts[0]
      return {
        app,
        bundleId,
        title: parts[2] || undefined
      }
    }
    return undefined
  } catch (err) {
    const errStr = String(err)
    // Check for permission errors
    if (errStr.includes('not allowed') || errStr.includes('assistive')) {
      logger.debug('AppleScript permission error', { error: errStr.substring(0, 200) })
      return undefined
    }
    // Other errors (no window, etc)
    logger.debug('AppleScript error', { error: errStr.substring(0, 200) })
    return undefined
  }
}

/** Get browser URL using AppleScript (browser-specific) */
async function getBrowserUrl(bundleId: string): Promise<string | undefined> {
  let script: string | undefined

  if (bundleId?.includes('chrome') || bundleId?.includes('Chrome')) {
    script = `tell application "Google Chrome" to return URL of active tab of front window`
  } else if (bundleId?.includes('safari') || bundleId === 'com.apple.Safari') {
    script = `tell application "Safari" to return URL of front document`
  } else if (bundleId?.includes('arc') || bundleId === 'company.thebrowser.Browser') {
    script = `tell application "Arc" to return URL of active tab of front window`
  }

  if (!script) return undefined

  try {
    const { stdout } = await execFileAsync('osascript', ['-e', script], { timeout: 2000 })
    return stdout.trim() || undefined
  } catch {
    return undefined
  }
}

interface GetWindowResult {
  window?: WindowInfo & { url?: string }
  permissionError?: boolean
}

async function getActiveWindowSafe(): Promise<GetWindowResult> {
  const win = await getActiveWindowAppleScript()
  if (!win) return {}

  // Try to get URL for browsers
  if (win.bundleId) {
    const url = await getBrowserUrl(win.bundleId)
    if (url) {
      return { window: { ...win, url } }
    }
  }

  return { window: win }
}

class TrackerService {
  private pollTimer: NodeJS.Timeout | null = null
  private isRunning = false
  private lastRecord: WindowActivityRecord | null = null

  /** Start tracking if enabled in config */
  async start(): Promise<void> {
    const config = this.getConfig()
    if (!config.enabled) {
      logger.info('Tracker disabled in config')
      return
    }
    if (this.isRunning) return

    // Check accessibility permission first (without triggering prompt)
    const permStatus = permissionManager.checkAccessibility()
    if (!permissionManager.hasAccessibility()) {
      logger.warn('Tracker disabled: missing accessibility permission', { status: permStatus })
      permissionManager.notifyMissingPermission()
      return
    }

    // Test if AppleScript works (retry a few times as permission may take time to propagate)
    let testPassed = false
    for (let i = 0; i < 3; i++) {
      const testResult = await getActiveWindowSafe()
      if (testResult.window) {
        logger.debug('AppleScript test passed', { app: testResult.window.app, attempt: i + 1 })
        testPassed = true
        break
      }
      if (i < 2) await new Promise((r) => setTimeout(r, 500))
    }
    if (!testPassed) {
      logger.warn('Cannot get active window after retries, tracker may not work properly')
    }

    trackerDataManager.init()
    trackerDataManager.startAutoFlush()
    this.startPolling(config.pollInterval)
    this.isRunning = true
    logger.info('TrackerService started', { pollInterval: config.pollInterval })
  }

  /** Stop tracking and flush data */
  stop(): void {
    if (!this.isRunning) return

    this.stopPolling()
    this.finalizeLastRecord()
    trackerDataManager.shutdown()
    this.isRunning = false
    this.lastRecord = null
    logger.info('TrackerService stopped')
  }

  /** Check if tracker is currently running */
  getStatus(): { enabled: boolean; running: boolean; permissionGranted: boolean } {
    return {
      enabled: this.getConfig().enabled,
      running: this.isRunning,
      permissionGranted: permissionManager.hasAccessibility()
    }
  }

  /** Handle config changes */
  onConfigUpdate(): void {
    const config = this.getConfig()
    if (config.enabled && !this.isRunning) {
      this.start()
    } else if (!config.enabled && this.isRunning) {
      this.stop()
    } else if (this.isRunning) {
      // Update poll interval if changed
      this.stopPolling()
      this.startPolling(config.pollInterval)
    }
  }

  private getConfig(): TrackerConfig {
    return configManager.get().tracker
  }

  private startPolling(intervalSeconds: number): void {
    this.pollTimer = setInterval(() => this.tick(), intervalSeconds * 1000)
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }

  private async tick(): Promise<void> {
    const config = this.getConfig()

    // Check idle state
    const idleTime = powerMonitor.getSystemIdleTime()
    if (idleTime >= config.idleThreshold) {
      this.finalizeLastRecord()
      return
    }

    // Get active window
    const result = await getActiveWindowSafe()

    if (!result.window) {
      this.finalizeLastRecord()
      return
    }

    const win = result.window

    // Build current activity
    const now = new Date().toISOString()
    const current = this.buildRecord(win, now, config)

    // Merge or create new
    if (this.lastRecord && this.isSameActivity(this.lastRecord, current)) {
      trackerDataManager.updateLastRecordEndTime(now)
      this.lastRecord.endTime = now
      this.lastRecord.duration = Math.round(
        (new Date(now).getTime() - new Date(this.lastRecord.startTime).getTime()) / 1000
      )
    } else {
      this.finalizeLastRecord()
      trackerDataManager.addRecord(current)
      this.lastRecord = current
    }
  }

  private buildRecord(
    win: WindowInfo & { url?: string },
    now: string,
    config: TrackerConfig
  ): WindowActivityRecord {
    const record: WindowActivityRecord = {
      startTime: now,
      endTime: now,
      duration: 0,
      app: win.app,
      bundleId: win.bundleId
    }

    if (config.recordTitle && win.title) {
      record.title = win.title
    }

    // Enrich context for apps in ENRICH_BUNDLE_IDS or config.enrichApps
    const shouldEnrich =
      (win.bundleId && ENRICH_BUNDLE_IDS.has(win.bundleId)) || config.enrichApps.includes(win.app)
    if (shouldEnrich) {
      record.context = this.extractContext(win)
    }

    return record
  }

  private extractContext(win: WindowInfo & { url?: string }): ActivityContext | undefined {
    const ctx: ActivityContext = {}

    // Always preserve raw title for AI fallback
    if (win.title) {
      ctx.rawTitle = win.title
    }

    // VSCode/Cursor: extract file and project from title (format: "filename — project-name")
    const isVSCodeLike =
      win.bundleId === 'com.microsoft.VSCode' ||
      win.bundleId === 'com.microsoft.VSCodeInsiders' ||
      win.bundleId === 'com.todesktop.230313mzl4w4u92'
    if (isVSCodeLike && win.title) {
      const parts = win.title.split(' — ')
      if (parts.length >= 2) {
        ctx.file = parts[0].trim() // filename
        ctx.project = parts[parts.length - 1].trim() // project name (last part)
      } else if (parts.length === 1) {
        ctx.file = parts[0].trim()
      }
    }

    // Browser: extract URL, domain, and page title
    if (win.url) {
      ctx.url = win.url
      try {
        const urlObj = new URL(win.url)
        ctx.domain = urlObj.hostname.replace(/^www\./, '')
      } catch {
        // Invalid URL, skip domain extraction
      }
      // For browsers, use window title as page title (file field)
      if (win.title && !ctx.file) {
        ctx.file = win.title
      }
    }

    return Object.keys(ctx).length > 0 ? ctx : undefined
  }

  private isSameActivity(a: WindowActivityRecord, b: WindowActivityRecord): boolean {
    if (a.app !== b.app) return false

    // For enriched apps, compare at file level for granular tracking
    if (a.context?.file !== b.context?.file) return false

    return true
  }

  private finalizeLastRecord(): void {
    if (this.lastRecord) {
      // Record is already in buffer via addRecord, just clear reference
      this.lastRecord = null
    }
  }
}

export const trackerService = new TrackerService()
