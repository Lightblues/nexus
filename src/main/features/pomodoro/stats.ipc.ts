import { ipcMain } from 'electron'
import { statsService } from './StatsService'
import { mainWindow } from '../../core'
import { logger } from '../../core'

export function registerStatsIPC(): void {
  ipcMain.handle('stats:get-today', () => {
    return statsService.getTodayStats()
  })

  ipcMain.handle('stats:get-weekly', () => {
    return statsService.getWeeklyStats()
  })

  ipcMain.handle('stats:get-activity', (_event, months?: number) => {
    return statsService.getActivityData(months)
  })

  ipcMain.handle('stats:get-timeline', (_event, date?: string) => {
    return statsService.getTimelineData(date)
  })

  ipcMain.handle('window:open-stats', () => {
    mainWindow.show()
  })

  ipcMain.handle('stats:get-sessions', (_event, date?: string) => {
    return statsService.getSessionsForDateFull(date)
  })

  ipcMain.handle('stats:update-session', (_event, id: string, updates: Record<string, unknown>) => {
    return statsService.updateSession(id, updates)
  })

  logger.info('Stats IPC handlers registered')
}
