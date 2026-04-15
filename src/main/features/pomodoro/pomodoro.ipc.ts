import { ipcMain, Notification } from 'electron'
import { pomodoroService, type PomodoroSession } from './PomodoroService'
import { configManager, dataManager, logger } from '../../core'
import { popupWindow } from '../../core/PopupWindow'

export function registerPomodoroIPC(): void {
  ipcMain.handle('pomodoro:start', (_event, session?: PomodoroSession) => {
    pomodoroService.start(session)
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:pause', () => {
    pomodoroService.pause()
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:resume', () => {
    pomodoroService.resume()
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:finish-early', () => {
    pomodoroService.finishEarly()
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:exit', () => {
    pomodoroService.exit()
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:skip-break', () => {
    pomodoroService.skipBreak()
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:status', () => {
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:next-session-type', () => {
    return pomodoroService.getNextSessionType()
  })

  ipcMain.handle('pomodoro:stats', () => {
    return dataManager.getStats()
  })

  ipcMain.handle('pomodoro:next-options', () => {
    return pomodoroService.getNextOptions()
  })

  ipcMain.handle('pomodoro:update-session', (_event, updates: Partial<PomodoroSession>) => {
    pomodoroService.updateCurrentSession(updates)
    return pomodoroService.getStatus()
  })

  ipcMain.handle('pomodoro:get-projects', () => {
    return dataManager.getProjects()
  })

  ipcMain.handle('pomodoro:add-project', (_event, project: string) => {
    dataManager.addProject(project)
    return dataManager.getProjects()
  })

  ipcMain.handle('pomodoro:get-tags', () => {
    return dataManager.getTags()
  })

  ipcMain.handle('pomodoro:add-tag', (_event, tag: string) => {
    dataManager.addTag(tag)
    return dataManager.getTags()
  })

  ipcMain.handle('pomodoro:get-last-session', () => {
    return dataManager.getLastSession()
  })

  ipcMain.handle('config:get', () => {
    return configManager.get()
  })

  // Forward events to renderer
  pomodoroService.on('tick', (remainingSeconds: number) => {
    const win = popupWindow.getWindow()
    if (win) {
      win.webContents.send('pomodoro:tick', remainingSeconds)
    }
  })

  pomodoroService.on('status', (status) => {
    const win = popupWindow.getWindow()
    if (win) {
      win.webContents.send('pomodoro:status', status)
    }
  })

  pomodoroService.on('finished', (sessionType) => {
    const win = popupWindow.getWindow()
    if (win) {
      win.webContents.send('pomodoro:finished', sessionType)
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
