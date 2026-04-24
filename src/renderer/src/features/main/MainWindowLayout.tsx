import { useState, useEffect } from 'react'
import StatsView from '../stats/StatsView'
import { SettingsView } from '../settings'
import { TrackerView } from '../tracker'
import { ErrorBoundary } from '../../components'

type Tab = 'stats' | 'tracker' | 'settings'

interface NavItemProps {
  icon: string
  label: string
  active: boolean
  onClick: () => void
}

function NavItem({ icon, label, active, onClick }: NavItemProps) {
  return (
    <button
      onClick={onClick}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '10px',
        width: '100%',
        padding: '10px 16px',
        border: 'none',
        borderRadius: '6px',
        background: active ? 'var(--accent)' : 'transparent',
        color: active ? 'white' : 'var(--text-primary)',
        cursor: 'pointer',
        fontSize: '14px',
        fontWeight: active ? 500 : 400,
        textAlign: 'left',
        transition: 'background 0.15s ease'
      }}
      onMouseEnter={(e) => {
        if (!active) e.currentTarget.style.background = 'var(--bg-hover)'
      }}
      onMouseLeave={(e) => {
        if (!active) e.currentTarget.style.background = 'transparent'
      }}
    >
      <span style={{ fontSize: '18px' }}>{icon}</span>
      <span>{label}</span>
    </button>
  )
}

function getInitialTab(): Tab {
  const hash = window.location.hash
  if (hash === '#/settings') return 'settings'
  if (hash === '#/tracker') return 'tracker'
  return 'stats'
}

export default function MainWindowLayout() {
  const [activeTab, setActiveTab] = useState<Tab>(getInitialTab)

  useEffect(() => {
    const handleHashChange = () => {
      const hash = window.location.hash
      if (hash === '#/settings') setActiveTab('settings')
      else if (hash === '#/tracker') setActiveTab('tracker')
      else if (hash === '#/stats') setActiveTab('stats')
    }
    window.addEventListener('hashchange', handleHashChange)
    return () => window.removeEventListener('hashchange', handleHashChange)
  }, [])

  const handleTabChange = (tab: Tab) => {
    setActiveTab(tab)
    window.location.hash = `#/${tab}`
  }

  return (
    <div style={{ display: 'flex', height: '100%' }}>
      {/* Sidebar */}
      <div style={{
        width: '180px',
        flexShrink: 0,
        background: 'var(--bg-secondary)',
        borderRight: '1px solid var(--border)',
        padding: '16px 12px',
        display: 'flex',
        flexDirection: 'column'
      }}>
        <div style={{ marginBottom: '24px', padding: '0 4px' }}>
          <h1 style={{ fontSize: '16px', fontWeight: 600, margin: 0 }}>Nexus</h1>
        </div>
        <nav style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
          <NavItem
            icon="📊"
            label="Statistics"
            active={activeTab === 'stats'}
            onClick={() => handleTabChange('stats')}
          />
          <NavItem
            icon="⏱️"
            label="Time Tracker"
            active={activeTab === 'tracker'}
            onClick={() => handleTabChange('tracker')}
          />
          <NavItem
            icon="⚙️"
            label="Settings"
            active={activeTab === 'settings'}
            onClick={() => handleTabChange('settings')}
          />
        </nav>
      </div>

      {/* Content */}
      <div style={{ flex: 1, overflow: 'hidden' }}>
        {activeTab === 'stats' && (
          <ErrorBoundary fallbackLabel="Statistics">
            <StatsView />
          </ErrorBoundary>
        )}
        {activeTab === 'tracker' && (
          <ErrorBoundary fallbackLabel="Time Tracker">
            <TrackerView />
          </ErrorBoundary>
        )}
        {activeTab === 'settings' && (
          <ErrorBoundary fallbackLabel="Settings">
            <SettingsView />
          </ErrorBoundary>
        )}
      </div>
    </div>
  )
}
