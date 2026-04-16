import { ipcMain, Notification } from 'electron'
import { IPC } from '@shared/ipc'
import { pomodoroService } from './PomodoroService'
import { configManager, dataManager, logger } from '../../core'
import { popupWindow } from '../../core/PopupWindow'
import type { PomodoroSession } from '@shared/types'

export function registerPomodoroIPC(): void {
  ipcMain.handle(IPC.pomodoro.start, (_event, session?: PomodoroSession) => {
    pomodoroService.start(session)
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.pause, () => {
    pomodoroService.pause()
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.resume, () => {
    pomodoroService.resume()
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.finishEarly, () => {
    pomodoroService.finishEarly()
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.exit, () => {
    pomodoroService.exit()
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.skipBreak, () => {
    pomodoroService.skipBreak()
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.status, () => {
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.nextSessionType, () => {
    return pomodoroService.getNextSessionType()
  })

  ipcMain.handle(IPC.pomodoro.stats, () => {
    return dataManager.getStats()
  })

  ipcMain.handle(IPC.pomodoro.nextOptions, () => {
    return pomodoroService.getNextOptions()
  })

  ipcMain.handle(IPC.pomodoro.updateSession, (_event, updates: Partial<PomodoroSession>) => {
    pomodoroService.updateCurrentSession(updates)
    return pomodoroService.getStatus()
  })

  ipcMain.handle(IPC.pomodoro.getProjects, () => {
    return dataManager.getProjects()
  })

  ipcMain.handle(IPC.pomodoro.addProject, (_event, project: string) => {
    dataManager.addProject(project)
    return dataManager.getProjects()
  })

  ipcMain.handle(IPC.pomodoro.getTags, () => {
    return dataManager.getTags()
  })

  ipcMain.handle(IPC.pomodoro.addTag, (_event, tag: string) => {
    dataManager.addTag(tag)
    return dataManager.getTags()
  })

  ipcMain.handle(IPC.pomodoro.getLastSession, () => {
    return dataManager.getLastSession()
  })

  ipcMain.handle(IPC.config.get, () => {
    return configManager.get()
  })

  // Forward events to renderer
  pomodoroService.on('tick', (remainingSeconds: number) => {
    const win = popupWindow.getWindow()
    if (win) {
      win.webContents.send(IPC.pomodoro.tick, remainingSeconds)
    }
  })

  pomodoroService.on('status', (status) => {
    const win = popupWindow.getWindow()
    if (win) {
      win.webContents.send(IPC.pomodoro.status, status)
    }
  })

  pomodoroService.on('finished', (sessionType) => {
    const win = popupWindow.getWindow()
    if (win) {
      win.webContents.send(IPC.pomodoro.finished, sessionType)
    }
    // System notification
    const options = pomodoroService.getNextOptions()
    const title = sessionType === 'work' ? 'Work Session Complete!' : 'Break Time Over!'
    const body = sessionType === 'work'
      ? `Time for a break. Click to ${options[0].label.toLowerCase()}.`
      : `Ready to focus again? Click to ${options[0].label.toLowerCase()}.`
    const notification = new Notification({ title, body, silent: false })
    notification.on('click', () => {
      popupWindow.show()
    })
    notification.show()

    // Show popover if config enabled (without stealing focus)
    const config = configManager.get().pomodoro
    if (config.showPopoverOnComplete) {
      popupWindow.showInactive()
    }
  })

  logger.info('Pomodoro IPC handlers registered')
}
