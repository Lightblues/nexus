import { ipcMain } from 'electron'
import { trackerService } from './TrackerService'
import { trackerDataManager } from './TrackerDataManager'
import { logger } from '../../core'

export function registerTrackerIPC(): void {
  ipcMain.handle('tracker:get-status', () => {
    return trackerService.getStatus()
  })

  ipcMain.handle('tracker:get-day', (_event, date: string) => {
    return trackerDataManager.getDay(date)
  })

  ipcMain.handle('tracker:get-date-range', (_event, startDate: string, endDate: string) => {
    return trackerDataManager.getDateRange(startDate, endDate)
  })

  ipcMain.handle('tracker:get-summary', (_event, startDate: string, endDate: string) => {
    return trackerDataManager.getAppSummary(startDate, endDate)
  })

  logger.info('Tracker IPC handlers registered')
}
