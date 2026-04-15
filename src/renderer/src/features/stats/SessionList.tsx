interface SessionRecord {
  id: string
  startTime: string
  endTime: string
  duration: number
  type: 'work' | 'shortBreak' | 'longBreak'
  completionType: 'normal' | 'early' | 'skipped'
  project?: string
  tags?: string[]
  task?: string
}

interface SessionListProps {
  sessions: SessionRecord[]
  onEdit: (session: SessionRecord) => void
}

function getTypeIcon(type: string): string {
  switch (type) {
    case 'work': return '🍅'
    case 'shortBreak': return '☕'
    case 'longBreak': return '🌴'
    default: return '⏱️'
  }
}

function formatTime(isoString: string): string {
  return new Date(isoString).toTimeString().slice(0, 5)
}

export default function SessionList({ sessions, onEdit }: SessionListProps) {
  if (sessions.length === 0) {
    return (
      <div style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '16px' }}>
        No sessions for this day
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
      <div style={{ fontSize: '14px', color: 'var(--text-secondary)', marginBottom: '4px' }}>
        Sessions ({sessions.length})
      </div>
      {sessions.map((session) => (
        <div
          key={session.id}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '12px',
            padding: '10px 12px',
            background: 'var(--bg-card)',
            borderRadius: '8px',
            fontSize: '13px'
          }}
        >
          <span style={{ fontSize: '16px' }}>{getTypeIcon(session.type)}</span>
          <span style={{ fontFamily: 'monospace', color: 'var(--text-primary)' }}>
            {formatTime(session.startTime)} - {formatTime(session.endTime)}
          </span>
          <span style={{ color: 'var(--text-secondary)' }}>
            {session.duration}m
          </span>
          <div style={{ flex: 1, display: 'flex', gap: '8px', alignItems: 'center', overflow: 'hidden' }}>
            {session.project && (
              <span style={{
                background: 'var(--accent)',
                color: 'white',
                padding: '2px 6px',
                borderRadius: '4px',
                fontSize: '11px'
              }}>
                {session.project}
              </span>
            )}
            {session.tags && session.tags.map((tag) => (
              <span
                key={tag}
                style={{
                  color: 'var(--text-secondary)',
                  fontSize: '11px'
                }}
              >
                #{tag}
              </span>
            ))}
            {session.task && (
              <span style={{
                color: 'var(--text-secondary)',
                fontSize: '12px',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap'
              }}>
                {session.task}
              </span>
            )}
          </div>
          <button
            onClick={() => onEdit(session)}
            style={{
              background: 'transparent',
              border: 'none',
              color: 'var(--text-secondary)',
              cursor: 'pointer',
              padding: '4px 8px',
              borderRadius: '4px',
              fontSize: '12px'
            }}
            onMouseOver={(e) => (e.currentTarget.style.background = 'var(--bg-primary)')}
            onMouseOut={(e) => (e.currentTarget.style.background = 'transparent')}
          >
            ✏️
          </button>
        </div>
      ))}
    </div>
  )
}
