import { useState } from 'react'
import { getAppColor, formatDuration } from './appColors'

interface ContextBreakdown {
  name: string
  duration: number
}

interface AppRankEntry {
  app: string
  duration: number
  percentage: number
  contexts?: ContextBreakdown[]
}

interface AppRankListProps {
  data: AppRankEntry[]
}

interface RankItemProps {
  rank: number
  entry: AppRankEntry
  maxDuration: number
}

function RankItem({ rank, entry, maxDuration }: RankItemProps) {
  const [expanded, setExpanded] = useState(false)
  const barWidth = (entry.duration / maxDuration) * 100
  const hasContexts = entry.contexts && entry.contexts.length > 0

  return (
    <div style={{ marginBottom: '12px' }}>
      <div
        onClick={() => hasContexts && setExpanded(!expanded)}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          cursor: hasContexts ? 'pointer' : 'default',
          padding: '8px 0'
        }}
      >
        {/* Rank number */}
        <span
          style={{
            width: '20px',
            fontSize: '13px',
            color: 'var(--text-secondary)',
            textAlign: 'right'
          }}
        >
          {rank}
        </span>

        {/* App color indicator */}
        <div
          style={{
            width: '4px',
            height: '28px',
            background: getAppColor(entry.app),
            borderRadius: '2px',
            flexShrink: 0
          }}
        />

        {/* App name and bar */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginBottom: '4px'
            }}
          >
            <span
              style={{
                fontSize: '14px',
                fontWeight: 500,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap'
              }}
            >
              {entry.app}
              {hasContexts && (
                <span style={{ marginLeft: '6px', fontSize: '10px', color: 'var(--text-secondary)' }}>
                  {expanded ? '▼' : '▶'}
                </span>
              )}
            </span>
            <span style={{ fontSize: '13px', color: 'var(--text-secondary)', flexShrink: 0 }}>
              {formatDuration(entry.duration)}
            </span>
          </div>
          {/* Progress bar */}
          <div
            style={{
              height: '6px',
              background: 'var(--bg-secondary)',
              borderRadius: '3px',
              overflow: 'hidden'
            }}
          >
            <div
              style={{
                width: `${barWidth}%`,
                height: '100%',
                background: getAppColor(entry.app),
                borderRadius: '3px',
                transition: 'width 0.3s ease'
              }}
            />
          </div>
        </div>
      </div>

      {/* Expanded context breakdown */}
      {expanded && hasContexts && (
        <div style={{ marginLeft: '36px', marginTop: '4px' }}>
          {entry.contexts!.slice(0, 5).map((ctx, idx) => (
            <div
              key={idx}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '4px 0',
                fontSize: '12px',
                color: 'var(--text-secondary)'
              }}
            >
              <span
                style={{
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                  flex: 1,
                  marginRight: '8px'
                }}
              >
                {ctx.name}
              </span>
              <span style={{ flexShrink: 0 }}>{formatDuration(ctx.duration)}</span>
            </div>
          ))}
          {entry.contexts!.length > 5 && (
            <div style={{ fontSize: '11px', color: 'var(--text-secondary)', padding: '4px 0' }}>
              +{entry.contexts!.length - 5} more
            </div>
          )}
        </div>
      )}
    </div>
  )
}

export default function AppRankList({ data }: AppRankListProps) {
  if (data.length === 0) {
    return (
      <div style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '20px' }}>
        No apps recorded
      </div>
    )
  }

  const maxDuration = Math.max(...data.map((e) => e.duration))

  return (
    <div>
      {data.map((entry, index) => (
        <RankItem key={entry.app} rank={index + 1} entry={entry} maxDuration={maxDuration} />
      ))}
    </div>
  )
}
