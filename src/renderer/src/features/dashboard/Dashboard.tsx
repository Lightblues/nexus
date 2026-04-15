import { Card } from '../../components'

interface DashboardProps {
  onSelectPomodoro: () => void
  onSelectUploader: () => void
}

export default function Dashboard({ onSelectPomodoro, onSelectUploader }: DashboardProps) {
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <h1 style={{ fontSize: '18px', marginBottom: '16px', textAlign: 'center' }}>
        EA Nexus
      </h1>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', flex: 1 }}>
        <Card onClick={onSelectPomodoro} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ fontSize: '32px', marginBottom: '8px' }}>🍅</span>
          <span style={{ fontSize: '14px', fontWeight: 500 }}>Pomodoro</span>
        </Card>

        <Card onClick={onSelectUploader} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ fontSize: '32px', marginBottom: '8px' }}>🖼️</span>
          <span style={{ fontSize: '14px', fontWeight: 500 }}>Uploader</span>
        </Card>

        <Card style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', opacity: 0.5 }}>
          <span style={{ fontSize: '32px', marginBottom: '8px' }}>📝</span>
          <span style={{ fontSize: '14px', fontWeight: 500 }}>Notes</span>
          <span style={{ fontSize: '10px', color: 'var(--text-secondary)' }}>Coming soon</span>
        </Card>

        <Card onClick={() => window.api.window.openSettings()} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
          <span style={{ fontSize: '32px', marginBottom: '8px' }}>⚙️</span>
          <span style={{ fontSize: '14px', fontWeight: 500 }}>Settings</span>
        </Card>
      </div>
    </div>
  )
}
