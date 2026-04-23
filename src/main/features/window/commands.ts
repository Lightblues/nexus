import { commandRegistry } from '../../core'
import { mainWindow } from '../../core'

/**
 * Window navigation commands. Thin wrappers over MainWindow — same destinations
 * as the tray right-click menu and the popover dashboard, but reachable from
 * the palette and the URL scheme too.
 */
export function registerWindowCommands(): void {
  commandRegistry.registerMany([
    {
      id: 'window.openMain',
      title: 'Open Main Window',
      subtitle: 'Show the full dashboard (statistics)',
      group: 'Window',
      keywords: ['home', 'main', 'dashboard', 'open'],
      run: () => {
        mainWindow.show()
      }
    },
    {
      id: 'window.openStats',
      title: 'Open Statistics',
      subtitle: 'Activity calendar, weekly chart, timeline',
      group: 'Window',
      keywords: ['stats', 'history', 'chart'],
      run: () => {
        mainWindow.showWithRoute('/stats')
      }
    },
    {
      id: 'window.openTracker',
      title: 'Open Time Tracker',
      subtitle: 'Auto-tracked app usage',
      group: 'Window',
      keywords: ['tracker', 'activity', 'apps'],
      run: () => {
        mainWindow.showWithRoute('/tracker')
      }
    },
    {
      id: 'window.openSettings',
      title: 'Open Settings',
      subtitle: 'Edit config.yaml',
      group: 'Window',
      keywords: ['settings', 'preferences', 'config'],
      run: () => {
        mainWindow.showWithRoute('/settings')
      }
    }
  ])
}
