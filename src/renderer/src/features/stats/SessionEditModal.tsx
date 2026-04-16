import { useState, useEffect } from 'react'
import { Button } from '../../components'
import type { SessionRecord } from '@shared/types'

interface SessionEditModalProps {
  session: SessionRecord
  projects: string[]
  tags: string[]
  onSave: (id: string, updates: { startTime?: string; endTime?: string; project?: string; tags?: string[]; task?: string }) => void
  onCancel: () => void
}

function getTypeLabel(type: string): string {
  switch (type) {
    case 'work': return 'Focus'
    case 'shortBreak': return 'Short Break'
    case 'longBreak': return 'Long Break'
    default: return type
  }
}

function formatTimeForInput(isoString: string): string {
  return new Date(isoString).toTimeString().slice(0, 5)
}

function parseTimeToISO(date: string, time: string): string {
  return `${date}T${time}:00.000Z`
}

export default function SessionEditModal({ session, projects, tags: availableTags, onSave, onCancel }: SessionEditModalProps) {
  const date = session.startTime.split('T')[0]
  const [startTime, setStartTime] = useState(formatTimeForInput(session.startTime))
  const [endTime, setEndTime] = useState(formatTimeForInput(session.endTime))
  const [project, setProject] = useState(session.project || '')
  const [selectedTags, setSelectedTags] = useState<string[]>(session.tags || [])
  const [task, setTask] = useState(session.task || '')
  const [newTag, setNewTag] = useState('')
  const [error, setError] = useState('')

  // Calculate duration
  const calculateDuration = (): number => {
    const start = new Date(`${date}T${startTime}:00`).getTime()
    const end = new Date(`${date}T${endTime}:00`).getTime()
    return Math.round((end - start) / 60000)
  }

  const duration = calculateDuration()

  useEffect(() => {
    if (duration <= 0) {
      setError('End time must be after start time')
    } else {
      setError('')
    }
  }, [startTime, endTime, duration])

  const handleSave = () => {
    if (duration <= 0) return

    const updates: { startTime?: string; endTime?: string; project?: string; tags?: string[]; task?: string } = {}

    const newStartISO = parseTimeToISO(date, startTime)
    const newEndISO = parseTimeToISO(date, endTime)

    if (newStartISO !== session.startTime) updates.startTime = newStartISO
    if (newEndISO !== session.endTime) updates.endTime = newEndISO
    if (project !== (session.project || '')) updates.project = project || undefined
    if (JSON.stringify(selectedTags) !== JSON.stringify(session.tags || [])) updates.tags = selectedTags.length > 0 ? selectedTags : undefined
    if (task !== (session.task || '')) updates.task = task || undefined

    onSave(session.id, updates)
  }

  const handleToggleTag = (tag: string) => {
    setSelectedTags((prev) =>
      prev.includes(tag) ? prev.filter((t) => t !== tag) : [...prev, tag]
    )
  }

  const handleAddTag = () => {
    if (newTag.trim() && !selectedTags.includes(newTag.trim())) {
      setSelectedTags([...selectedTags, newTag.trim()])
      setNewTag('')
    }
  }

  const inputStyle = {
    background: 'var(--bg-card)',
    color: 'var(--text-primary)',
    border: '1px solid var(--border)',
    borderRadius: '6px',
    padding: '8px 10px',
    fontSize: '13px',
    width: '100%',
    outline: 'none'
  }

  const tagStyle = (selected: boolean) => ({
    padding: '4px 8px',
    borderRadius: '4px',
    fontSize: '12px',
    cursor: 'pointer',
    background: selected ? 'var(--accent)' : 'var(--bg-card)',
    color: selected ? 'white' : 'var(--text-primary)',
    border: '1px solid var(--border)'
  })

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.6)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000
      }}
      onClick={onCancel}
    >
      <div
        style={{
          background: 'var(--bg-primary)',
          borderRadius: '12px',
          padding: '24px',
          width: '380px',
          maxHeight: '90vh',
          overflow: 'auto'
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h2 style={{ fontSize: '18px', margin: 0 }}>Edit Session</h2>
          <button
            onClick={onCancel}
            style={{ background: 'transparent', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '18px' }}
          >
            ×
          </button>
        </div>

        {/* Type (read-only) */}
        <div style={{ marginBottom: '16px' }}>
          <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
            Type
          </label>
          <div style={{ fontSize: '14px', color: 'var(--text-primary)' }}>
            {getTypeLabel(session.type)}
          </div>
        </div>

        {/* Time inputs */}
        <div style={{ display: 'flex', gap: '12px', marginBottom: '16px' }}>
          <div style={{ flex: 1 }}>
            <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
              Start Time
            </label>
            <input
              type="time"
              value={startTime}
              onChange={(e) => setStartTime(e.target.value)}
              style={inputStyle}
            />
          </div>
          <div style={{ flex: 1 }}>
            <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
              End Time
            </label>
            <input
              type="time"
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
              style={inputStyle}
            />
          </div>
        </div>

        {/* Duration display */}
        <div style={{ marginBottom: '16px' }}>
          <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
            Duration
          </label>
          <div style={{ fontSize: '14px', color: duration > 0 ? 'var(--text-primary)' : 'var(--accent)' }}>
            {duration > 0 ? `${duration} min` : 'Invalid'}
          </div>
          {error && <div style={{ fontSize: '11px', color: 'var(--accent)', marginTop: '4px' }}>{error}</div>}
        </div>

        {/* Project */}
        <div style={{ marginBottom: '16px' }}>
          <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
            Project
          </label>
          <select
            value={project}
            onChange={(e) => setProject(e.target.value)}
            style={inputStyle}
          >
            <option value="">No project</option>
            {projects.map((p) => (
              <option key={p} value={p}>{p}</option>
            ))}
          </select>
        </div>

        {/* Tags */}
        <div style={{ marginBottom: '16px' }}>
          <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
            Tags
          </label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginBottom: '8px' }}>
            {availableTags.map((tag) => (
              <span
                key={tag}
                onClick={() => handleToggleTag(tag)}
                style={tagStyle(selectedTags.includes(tag))}
              >
                {tag}
              </span>
            ))}
            {selectedTags.filter((t) => !availableTags.includes(t)).map((tag) => (
              <span
                key={tag}
                onClick={() => handleToggleTag(tag)}
                style={tagStyle(true)}
              >
                {tag}
              </span>
            ))}
          </div>
          <div style={{ display: 'flex', gap: '8px' }}>
            <input
              type="text"
              placeholder="Add tag..."
              value={newTag}
              onChange={(e) => setNewTag(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleAddTag()}
              style={{ ...inputStyle, flex: 1 }}
            />
          </div>
        </div>

        {/* Task */}
        <div style={{ marginBottom: '24px' }}>
          <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
            Task Description
          </label>
          <input
            type="text"
            placeholder="What were you working on?"
            value={task}
            onChange={(e) => setTask(e.target.value)}
            style={inputStyle}
          />
        </div>

        {/* Buttons */}
        <div style={{ display: 'flex', gap: '12px', justifyContent: 'flex-end' }}>
          <Button variant="ghost" onClick={onCancel}>Cancel</Button>
          <Button onClick={handleSave} disabled={duration <= 0}>Save</Button>
        </div>
      </div>
    </div>
  )
}
