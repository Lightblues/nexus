import { ipcMain } from 'electron'
import { IPC } from '@shared/ipc'
import { statsService } from './StatsService'
import { mainWindow } from '../../core'
import { logger } from '../../core'

export function registerStatsIPC(): void {
  ipcMain.handle(IPC.stats.getToday, () => {
    return statsService.getTodayStats()
  })

  ipcMain.handle(IPC.stats.getWeekly, () => {
    return statsService.getWeeklyStats()
  })

  ipcMain.handle(IPC.stats.getActivity, (_event, months?: number) => {
    return statsService.getActivityData(months)
  })

  ipcMain.handle(IPC.stats.getTimeline, (_event, date?: string) => {
    return statsService.getTimelineData(date)
  })

  ipcMain.handle(IPC.window.openStats, () => {
    mainWindow.show()
  })

  ipcMain.handle(IPC.stats.getSessions, (_event, date?: string) => {
    return statsService.getSessionsForDateFull(date)
  })

  ipcMain.handle(IPC.stats.updateSession, (_event, id: string, updates: Record<string, unknown>) => {
    return statsService.updateSession(id, updates)
  })

  logger.info('Stats IPC handlers registered')
}
