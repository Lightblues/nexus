import { useState } from 'react'
import { getAppColor, formatDuration } from './appColors'

interface ActivityContext {
  project?: string
  file?: string
  domain?: string
}

interface TrackerTimelineSegment {
  startTime: string
  endTime: string
  app: string
  duration: number
  context?: ActivityContext
}

interface TrackerTimelineProps {
  data: TrackerTimelineSegment[]
}

const HOURS = Array.from({ length: 25 }, (_, i) => i)
const MINUTES_IN_DAY = 24 * 60

function timeToMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map(Number)
  return hours * 60 + minutes
}

export default function TrackerTimeline({ data }: TrackerTimelineProps) {
  const [hoveredSegment, setHoveredSegment] = useState<TrackerTimelineSegment | null>(null)
  const [tooltipPos, setTooltipPos] = useState({ x: 0, y: 0 })

  if (data.length === 0) {
    return (
      <div style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '20px' }}>
        No activity recorded for this day.
      </div>
    )
  }

  const handleMouseEnter = (segment: TrackerTimelineSegment, e: React.MouseEvent) => {
    setHoveredSegment(segment)
    setTooltipPos({ x: e.clientX, y: e.clientY })
  }

  const handleMouseMove = (e: React.MouseEvent) => {
    if (hoveredSegment) {
      setTooltipPos({ x: e.clientX, y: e.clientY })
    }
  }

  const handleMouseLeave = () => {
    setHoveredSegment(null)
  }

  // Get unique apps for legend
  const uniqueApps = [...new Set(data.map((s) => s.app))]

  return (
    <div style={{ position: 'relative' }}>
      {/* Hour labels */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          marginBottom: '4px',
          fontSize: '10px',
          color: 'var(--text-secondary)'
        }}
      >
        {HOURS.filter((h) => h % 4 === 0).map((hour) => (
          <span key={hour} style={{ width: '30px', textAlign: 'center' }}>
            {hour.toString().padStart(2, '0')}:00
          </span>
        ))}
      </div>

      {/* Timeline bar */}
      <div
        style={{
          position: 'relative',
          height: '32px',
          background: 'var(--bg-card)',
          borderRadius: '4px',
          overflow: 'hidden'
        }}
      >
        {data.map((segment, index) => {
          const startMinutes = timeToMinutes(segment.startTime)
          const endMinutes = timeToMinutes(segment.endTime)
          const left = (startMinutes / MINUTES_IN_DAY) * 100
          const width = ((endMinutes - startMinutes) / MINUTES_IN_DAY) * 100

          return (
            <div
              key={index}
              onMouseEnter={(e) => handleMouseEnter(segment, e)}
              onMouseMove={handleMouseMove}
              onMouseLeave={handleMouseLeave}
              style={{
                position: 'absolute',
                left: `${left}%`,
                width: `${Math.max(width, 0.3)}%`,
                height: '100%',
                background: getAppColor(segment.app),
                cursor: 'pointer',
                transition: 'opacity 0.15s',
                opacity: hoveredSegment === segment ? 0.8 : 1
              }}
            />
          )
        })}
      </div>

      {/* Legend */}
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '12px',
          marginTop: '12px',
          fontSize: '12px'
        }}
      >
        {uniqueApps.slice(0, 8).map((app) => (
          <div key={app} style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
            <div
              style={{
                width: '12px',
                height: '12px',
                background: getAppColor(app),
                borderRadius: '2px'
              }}
            />
            <span style={{ color: 'var(--text-secondary)' }}>{app}</span>
          </div>
        ))}
        {uniqueApps.length > 8 && (
          <span style={{ color: 'var(--text-secondary)' }}>+{uniqueApps.length - 8} more</span>
        )}
      </div>

      {/* Tooltip */}
      {hoveredSegment && (
        <div
          style={{
            position: 'fixed',
            left: tooltipPos.x + 10,
            top: tooltipPos.y - 60,
            background: 'var(--bg-primary)',
            border: '1px solid var(--border)',
            borderRadius: '6px',
            padding: '8px 12px',
            fontSize: '12px',
            zIndex: 1000,
            pointerEvents: 'none',
            boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
            maxWidth: '250px'
          }}
        >
          <div style={{ fontWeight: 500, display: 'flex', alignItems: 'center', gap: '6px' }}>
            <div
              style={{
                width: '8px',
                height: '8px',
                background: getAppColor(hoveredSegment.app),
                borderRadius: '2px'
              }}
            />
            {hoveredSegment.app}
          </div>
          <div style={{ color: 'var(--text-secondary)', marginTop: '4px' }}>
            {hoveredSegment.startTime} - {hoveredSegment.endTime} ({formatDuration(hoveredSegment.duration)})
          </div>
          {hoveredSegment.context?.project && (
            <div style={{ color: 'var(--text-secondary)', marginTop: '2px' }}>
              📁 {hoveredSegment.context.project}
            </div>
          )}
          {hoveredSegment.context?.file && (
            <div
              style={{
                color: 'var(--text-secondary)',
                marginTop: '2px',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap'
              }}
            >
              📄 {hoveredSegment.context.file}
            </div>
          )}
          {hoveredSegment.context?.domain && (
            <div style={{ color: 'var(--text-secondary)', marginTop: '2px' }}>
              🌐 {hoveredSegment.context.domain}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
