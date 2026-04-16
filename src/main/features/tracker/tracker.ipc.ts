import { ipcMain } from 'electron'
import { IPC } from '@shared/ipc'
import { trackerService } from './TrackerService'
import { trackerDataManager } from './TrackerDataManager'
import { logger } from '../../core'

export function registerTrackerIPC(): void {
  ipcMain.handle(IPC.tracker.getStatus, () => {
    return trackerService.getStatus()
  })

  ipcMain.handle(IPC.tracker.getDay, (_event, date: string) => {
    return trackerDataManager.getDay(date)
  })

  ipcMain.handle(IPC.tracker.getDateRange, (_event, startDate: string, endDate: string) => {
    return trackerDataManager.getDateRange(startDate, endDate)
  })

  ipcMain.handle(IPC.tracker.getSummary, (_event, startDate: string, endDate: string) => {
    return trackerDataManager.getAppSummary(startDate, endDate)
  })

  logger.info('Tracker IPC handlers registered')
}
