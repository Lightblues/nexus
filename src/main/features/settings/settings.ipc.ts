import * as fs from 'fs'
import * as yaml from 'js-yaml'
import { ipcMain } from 'electron'
import { IPC } from '@shared/ipc'
import { pathManager, logger } from '../../core'
import { mainWindow } from '../../core/MainWindow'
import type { ValidationResult, WriteResult } from '@shared/types'

function validateConfig(content: string): ValidationResult {
  let parsed: unknown
  try {
    parsed = yaml.load(content)
  } catch (err) {
    return { valid: false, error: `YAML syntax error: ${(err as Error).message}` }
  }
  if (typeof parsed !== 'object' || parsed === null) {
    return { valid: false, error: 'Config must be a YAML object' }
  }
  const config = parsed as Record<string, unknown>
  if (!config.pomodoro || typeof config.pomodoro !== 'object') {
    return { valid: false, error: 'Missing required section: pomodoro' }
  }
  const pomodoro = config.pomodoro as Record<string, unknown>
  const requiredPomodoroFields = ['workDuration', 'shortBreakDuration', 'longBreakDuration', 'sessionsBeforeLongBreak']
  for (const field of requiredPomodoroFields) {
    if (typeof pomodoro[field] !== 'number') {
      return { valid: false, error: `pomodoro.${field} must be a number` }
    }
  }
  if (pomodoro.projects !== undefined && !Array.isArray(pomodoro.projects)) {
    return { valid: false, error: 'pomodoro.projects must be an array' }
  }
  if (pomodoro.tags !== undefined && !Array.isArray(pomodoro.tags)) {
    return { valid: false, error: 'pomodoro.tags must be an array' }
  }
  if (config.ui !== undefined) {
    if (typeof config.ui !== 'object') {
      return { valid: false, error: 'ui must be an object' }
    }
    const ui = config.ui as Record<string, unknown>
    if (ui.windowWidth !== undefined && typeof ui.windowWidth !== 'number') {
      return { valid: false, error: 'ui.windowWidth must be a number' }
    }
    if (ui.windowHeight !== undefined && typeof ui.windowHeight !== 'number') {
      return { valid: false, error: 'ui.windowHeight must be a number' }
    }
  }
  return { valid: true }
}

export function registerSettingsIPC(): void {
  ipcMain.handle(IPC.config.readRaw, () => {
    const configPath = pathManager.configPath
    try {
      if (!fs.existsSync(configPath)) {
        return ''
      }
      return fs.readFileSync(configPath, 'utf-8')
    } catch (err) {
      logger.error('Failed to read config file', err)
      return ''
    }
  })

  ipcMain.handle(IPC.config.validate, (_event, content: string): ValidationResult => {
    return validateConfig(content)
  })

  ipcMain.handle(IPC.config.writeRaw, (_event, content: string): WriteResult => {
    const validation = validateConfig(content)
    if (!validation.valid) {
      return { success: false, error: validation.error }
    }
    const configPath = pathManager.configPath
    try {
      fs.writeFileSync(configPath, content, 'utf-8')
      logger.info('Config file written via settings editor')
      return { success: true }
    } catch (err) {
      logger.error('Failed to write config file', err)
      return { success: false, error: `Write failed: ${(err as Error).message}` }
    }
  })

  ipcMain.handle(IPC.window.openSettings, () => {
    mainWindow.showWithRoute('/settings')
  })

  logger.info('Settings IPC handlers registered')
}
