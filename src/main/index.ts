import { app } from 'electron'
import { pathManager, configManager, dataManager, logger, trayManager, popupWindow, mainWindow } from './core'
import { registerPomodoroIPC, registerStatsIPC } from './features/pomodoro'
import { registerSettingsIPC } from './features/settings'
import { trackerService, registerTrackerIPC } from './features/tracker'
import { uploaderService, registerUploaderIPC } from './features/uploader'

// Prevent multiple instances
const gotTheLock = app.requestSingleInstanceLock()
if (!gotTheLock) {
  app.quit()
}


app.whenReady().then(() => {
  try {
    // Initialize core
    pathManager.ensureDirectories()
    logger.init()
    configManager.load()
    configManager.watch()
    dataManager.init()

    // Initialize UI
    trayManager.init()
    popupWindow.create()

    // Register IPC
    registerPomodoroIPC()
    registerStatsIPC()
    registerSettingsIPC()
    registerTrackerIPC()
    registerUploaderIPC()

    // Start services
    trackerService.start()
    uploaderService.init()
    configManager.on('config:updated', () => trackerService.onConfigUpdate())

    logger.info('EA Nexus started')
  } catch (err) {
    console.error('Failed to initialize:', err)
  }
})

app.on('window-all-closed', () => {
  // Keep app running (menu bar app)
})

// macOS: Show main window when clicking Dock icon
app.on('activate', () => {
  mainWindow.show()
})

app.on('before-quit', () => {
  trackerService.stop()
  configManager.stopWatching()
  trayManager.destroy()
  popupWindow.destroy()
  mainWindow.destroy()
  logger.info('EA Nexus shutting down')
})
