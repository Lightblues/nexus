import { useState } from 'react'

interface TimelineSegment {
  startTime: string
  endTime: string
  type: 'work' | 'shortBreak' | 'longBreak'
  duration: number
  project?: string
}

interface DailyTimelineProps {
  data: TimelineSegment[]
}

const HOURS = Array.from({ length: 25 }, (_, i) => i)
const MINUTES_IN_DAY = 24 * 60

function timeToMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map(Number)
  return hours * 60 + minutes
}

function getTypeLabel(type: string): string {
  switch (type) {
    case 'work': return 'Focus'
    case 'shortBreak': return 'Short Break'
    case 'longBreak': return 'Long Break'
    default: return type
  }
}

function getTypeColor(type: string): string {
  switch (type) {
    case 'work': return 'var(--accent)'
    case 'shortBreak': return 'var(--success, #4ade80)'
    case 'longBreak': return 'var(--success, #22c55e)'
    default: return 'var(--bg-card)'
  }
}

export default function DailyTimeline({ data }: DailyTimelineProps) {
  const [hoveredSegment, setHoveredSegment] = useState<TimelineSegment | null>(null)
  const [tooltipPos, setTooltipPos] = useState({ x: 0, y: 0 })

  if (data.length === 0) {
    return (
      <div style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '20px' }}>
        No sessions recorded for this day.
      </div>
    )
  }

  const handleMouseEnter = (segment: TimelineSegment, e: React.MouseEvent) => {
    setHoveredSegment(segment)
    setTooltipPos({ x: e.clientX, y: e.clientY })
  }

  const handleMouseLeave = () => {
    setHoveredSegment(null)
  }

  return (
    <div style={{ position: 'relative' }}>
      {/* Hour labels */}
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', fontSize: '10px', color: 'var(--text-secondary)' }}>
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
              onMouseLeave={handleMouseLeave}
              style={{
                position: 'absolute',
                left: `${left}%`,
                width: `${Math.max(width, 0.5)}%`,
                height: '100%',
                background: getTypeColor(segment.type),
                cursor: 'pointer',
                transition: 'opacity 0.15s',
                opacity: hoveredSegment === segment ? 0.8 : 1
              }}
            />
          )
        })}
      </div>

      {/* Legend */}
      <div style={{ display: 'flex', gap: '16px', marginTop: '12px', fontSize: '12px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
          <div style={{ width: '12px', height: '12px', background: 'var(--accent)', borderRadius: '2px' }} />
          <span style={{ color: 'var(--text-secondary)' }}>Focus</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
          <div style={{ width: '12px', height: '12px', background: 'var(--success, #4ade80)', borderRadius: '2px' }} />
          <span style={{ color: 'var(--text-secondary)' }}>Break</span>
        </div>
      </div>

      {/* Tooltip */}
      {hoveredSegment && (
        <div
          style={{
            position: 'fixed',
            left: tooltipPos.x + 10,
            top: tooltipPos.y - 40,
            background: 'var(--bg-primary)',
            border: '1px solid var(--border)',
            borderRadius: '6px',
            padding: '8px 12px',
            fontSize: '12px',
            zIndex: 1000,
            pointerEvents: 'none',
            boxShadow: '0 4px 12px rgba(0,0,0,0.3)'
          }}
        >
          <div style={{ fontWeight: 500 }}>
            {hoveredSegment.startTime} - {hoveredSegment.endTime}
          </div>
          <div style={{ color: 'var(--text-secondary)', marginTop: '2px' }}>
            {getTypeLabel(hoveredSegment.type)}
            {hoveredSegment.project && ` · ${hoveredSegment.project}`}
          </div>
          <div style={{ color: 'var(--text-secondary)', marginTop: '2px' }}>
            {hoveredSegment.duration} min
          </div>
        </div>
      )}
    </div>
  )
}
