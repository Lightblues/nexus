import { app } from 'electron'
import {
  pathManager,
  configManager,
  dataManager,
  logger,
  trayManager,
  popupWindow,
  mainWindow,
  paletteWindow,
  globalHotkey,
  urlSchemeHandler
} from './core'
import { registerPomodoroIPC, registerStatsIPC, registerPomodoroCommands } from './features/pomodoro'
import { registerSettingsIPC } from './features/settings'
import { trackerService, registerTrackerIPC } from './features/tracker'
import { uploaderService, registerUploaderIPC } from './features/uploader'
import { registerPaletteIPC } from './features/palette'

// Prevent multiple instances (required so URL-scheme 'second-instance' event fires)
const gotTheLock = app.requestSingleInstanceLock()
if (!gotTheLock) {
  app.quit()
}

// Register URL scheme early — `open-url` can fire before app.whenReady()
urlSchemeHandler.register()


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
    paletteWindow.create()

    // Register commands (must come before IPC registration that reads the registry)
    registerPomodoroCommands()

    // Register IPC
    registerPomodoroIPC()
    registerStatsIPC()
    registerSettingsIPC()
    registerTrackerIPC()
    registerUploaderIPC()
    registerPaletteIPC()

    // Start services
    trackerService.start()
    uploaderService.init()
    globalHotkey.register()
    configManager.on('config:updated', () => {
      trackerService.onConfigUpdate()
      globalHotkey.reload()
    })

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
  globalHotkey.destroy()
  trayManager.destroy()
  popupWindow.destroy()
  paletteWindow.destroy()
  mainWindow.destroy()
  logger.info('EA Nexus shutting down')
})
