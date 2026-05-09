import * as fs from 'fs'
import { screen } from 'electron'
import { pathManager } from './PathManager'
import { logger } from './Logger'

export interface WindowState {
  x: number
  y: number
  width: number
  height: number
  isMaximized: boolean
}

class WindowStateManager {
  load(): WindowState | null {
    try {
      const filePath = pathManager.windowStatePath
      if (!fs.existsSync(filePath)) return null
      const content = fs.readFileSync(filePath, 'utf-8')
      const state = JSON.parse(content) as WindowState
      if (!this.isValidState(state)) return null
      if (!this.isVisibleOnDisplay(state)) return null
      return state
    } catch (err) {
      logger.error('Failed to load window state', err)
      return null
    }
  }

  save(state: WindowState): void {
    try {
      fs.writeFileSync(pathManager.windowStatePath, JSON.stringify(state, null, 2))
    } catch (err) {
      logger.error('Failed to save window state', err)
    }
  }

  private isValidState(state: unknown): state is WindowState {
    if (!state || typeof state !== 'object') return false
    const s = state as Record<string, unknown>
    return (
      typeof s.x === 'number' &&
      typeof s.y === 'number' &&
      typeof s.width === 'number' &&
      typeof s.height === 'number' &&
      typeof s.isMaximized === 'boolean' &&
      s.width > 0 &&
      s.height > 0
    )
  }

  private isVisibleOnDisplay(state: WindowState): boolean {
    const rect = { x: state.x, y: state.y, width: state.width, height: state.height }
    const display = screen.getDisplayMatching(rect)
    const { x, y, width, height } = display.workArea
    // Check that at least 100px of the window is within the display work area
    const overlapX = Math.max(0, Math.min(rect.x + rect.width, x + width) - Math.max(rect.x, x))
    const overlapY = Math.max(0, Math.min(rect.y + rect.height, y + height) - Math.max(rect.y, y))
    return overlapX > 100 && overlapY > 50
  }
}

export const windowStateManager = new WindowStateManager()
