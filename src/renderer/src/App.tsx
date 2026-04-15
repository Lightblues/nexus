import { useState, useEffect } from 'react'
import Dashboard from './features/dashboard/Dashboard'
import PomodoroView from './features/pomodoro/PomodoroView'
import { UploaderView } from './features/uploader'
import { MainWindowLayout } from './features/main'

type View = 'dashboard' | 'pomodoro' | 'uploader' | 'main'

function getInitialView(): View {
  // Check URL hash for MainWindow routes
  const hash = window.location.hash
  // Main window routes: stats, settings, tracker
  if (
    hash.startsWith('#/stats') ||
    hash.startsWith('#/settings') ||
    hash.startsWith('#/tracker')
  ) {
    return 'main'
  }
  // Check window size to detect MainWindow (larger than popup)
  // Popup is typically ~340x480, MainWindow is ~900x600
  if (window.innerWidth > 500) {
    return 'main'
  }
  return 'dashboard'
}

export default function App() {
  const [view, setView] = useState<View>(getInitialView)

  // Auto-switch to uploader view when image is dropped on tray
  useEffect(() => {
    if (getInitialView() !== 'main') {
      window.api.uploader.onImageDropped(() => {
        setView('uploader')
      })
    }
  }, [])

  // MainWindow with sidebar navigation (stats/settings)
  if (view === 'main') {
    return (
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        <MainWindowLayout />
      </div>
    )
  }

  // Popup window views (dashboard/pomodoro/uploader)
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      {view === 'dashboard' && (
        <Dashboard
          onSelectPomodoro={() => setView('pomodoro')}
          onSelectUploader={() => setView('uploader')}
        />
      )}
      {view === 'pomodoro' && <PomodoroView onBack={() => setView('dashboard')} />}
      {view === 'uploader' && <UploaderView onBack={() => setView('dashboard')} />}
    </div>
  )
}
