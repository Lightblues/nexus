import { useState, useEffect } from 'react'
import Dashboard from './features/dashboard/Dashboard'
import PomodoroView from './features/pomodoro/PomodoroView'
import { UploaderView } from './features/uploader'
import { MainWindowLayout } from './features/main'
import { ErrorBoundary } from './components'

type View = 'dashboard' | 'pomodoro' | 'uploader' | 'main'

function getInitialView(): View {
  const hash = window.location.hash
  // Main window routes: stats, settings, tracker
  if (
    hash.startsWith('#/stats') ||
    hash.startsWith('#/settings') ||
    hash.startsWith('#/tracker')
  ) {
    return 'main'
  }
  return 'dashboard'
}

export default function App() {
  const [view, setView] = useState<View>(getInitialView)

  // Auto-switch to uploader view when image is dropped on tray
  useEffect(() => {
    if (getInitialView() === 'main') return
    const cleanup = window.api.uploader.onImageDropped(() => {
      setView('uploader')
    })
    return cleanup
  }, [])

  // MainWindow with sidebar navigation (stats/settings)
  if (view === 'main') {
    return (
      <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
        <ErrorBoundary fallbackLabel="Main Window">
          <MainWindowLayout />
        </ErrorBoundary>
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
      {view === 'pomodoro' && (
        <ErrorBoundary fallbackLabel="Pomodoro">
          <PomodoroView onBack={() => setView('dashboard')} />
        </ErrorBoundary>
      )}
      {view === 'uploader' && (
        <ErrorBoundary fallbackLabel="Uploader">
          <UploaderView onBack={() => setView('dashboard')} />
        </ErrorBoundary>
      )}
    </div>
  )
}
