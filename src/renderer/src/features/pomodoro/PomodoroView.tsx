import { useState, useEffect } from 'react'
import { Button } from '../../components'
import type { PomodoroStatus, NextActionOption } from '@shared/types'

interface PomodoroViewProps {
  onBack: () => void
}

interface TodayStats {
  totalSessions: number
  totalMinutes: number
}

export default function PomodoroView({ onBack }: PomodoroViewProps) {
  const [status, setStatus] = useState<PomodoroStatus>({
    state: 'idle',
    sessionType: 'work',
    remainingSeconds: 0,
    totalSeconds: 0,
    completedSessions: 0
  })
  const [selectedProject, setSelectedProject] = useState<string>('')
  const [selectedTags, setSelectedTags] = useState<string[]>([])
  const [taskDescription, setTaskDescription] = useState<string>('')
  const [projects, setProjects] = useState<string[]>([])
  const [tags, setTags] = useState<string[]>([])
  const [newProject, setNewProject] = useState('')
  const [newTag, setNewTag] = useState('')
  const [showEditModal, setShowEditModal] = useState(false)
  const [showIdleConfig, setShowIdleConfig] = useState(false)
  const [nextOptions, setNextOptions] = useState<NextActionOption[]>([])
  const [todayStats, setTodayStats] = useState<TodayStats>({ totalSessions: 0, totalMinutes: 0 })

  const loadTodayStats = () => {
    window.api.stats.getToday().then((stats) => {
      setTodayStats({ totalSessions: stats.totalSessions, totalMinutes: stats.totalMinutes })
    })
  }

  useEffect(() => {
    // Load initial status and data
    window.api.pomodoro.getStatus().then((s) => {
      setStatus(s)
      // If already finished, load next options immediately
      if (s.state === 'finished') {
        window.api.pomodoro.getNextOptions().then(setNextOptions)
      }
    })
    window.api.pomodoro.getProjects().then(setProjects)
    window.api.pomodoro.getTags().then(setTags)
    window.api.pomodoro.getLastSession().then((last) => {
      if (last.project) setSelectedProject(last.project)
      if (last.tags) setSelectedTags(last.tags)
      if (last.task) setTaskDescription(last.task)
    })
    loadTodayStats()

    // Subscribe to updates (store cleanup functions)
    const cleanupTick = window.api.pomodoro.onTick((seconds) => {
      setStatus((prev) => ({ ...prev, remainingSeconds: seconds }))
    })
    const cleanupStatus = window.api.pomodoro.onStatus(setStatus)
    const cleanupFinished = window.api.pomodoro.onFinished(() => {
      window.api.pomodoro.getNextOptions().then(setNextOptions)
      loadTodayStats() // Refresh stats on session complete
    })

    return () => {
      cleanupTick()
      cleanupStatus()
      cleanupFinished()
    }
  }, [])

  const formatTime = (seconds: number): string => {
    const mins = Math.floor(seconds / 60)
    const secs = seconds % 60
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`
  }

  const handleStart = async () => {
    await window.api.pomodoro.start({
      type: 'work',
      project: selectedProject || undefined,
      tags: selectedTags.length > 0 ? selectedTags : undefined,
      task: taskDescription || undefined
    })
  }

  const handlePause = () => window.api.pomodoro.pause()
  const handleResume = () => window.api.pomodoro.resume()
  const handleFinishEarly = () => window.api.pomodoro.finishEarly()
  const handleExit = () => window.api.pomodoro.exit()
  const handleSkipBreak = () => window.api.pomodoro.skipBreak()

  const handleNextAction = async (option: NextActionOption) => {
    if (option.action === 'exit') {
      await window.api.pomodoro.exit()
    } else if (option.sessionType) {
      await window.api.pomodoro.start({
        type: option.sessionType,
        project: selectedProject || undefined,
        tags: selectedTags.length > 0 ? selectedTags : undefined,
        task: taskDescription || undefined
      })
    }
  }

  const handleAddProject = async () => {
    if (newProject.trim()) {
      const updated = await window.api.pomodoro.addProject(newProject.trim())
      setProjects(updated)
      setSelectedProject(newProject.trim())
      setNewProject('')
    }
  }

  const handleAddTag = async () => {
    if (newTag.trim() && !selectedTags.includes(newTag.trim())) {
      const updated = await window.api.pomodoro.addTag(newTag.trim())
      setTags(updated)
      setSelectedTags([...selectedTags, newTag.trim()])
      setNewTag('')
    }
  }

  const handleToggleTag = (tag: string) => {
    setSelectedTags(prev =>
      prev.includes(tag) ? prev.filter(t => t !== tag) : [...prev, tag]
    )
  }

  const handleSaveEdit = async () => {
    await window.api.pomodoro.updateSession({
      project: selectedProject || undefined,
      tags: selectedTags.length > 0 ? selectedTags : undefined,
      task: taskDescription || undefined
    })
    setShowEditModal(false)
  }

  const getSessionLabel = (type: string): string => {
    switch (type) {
      case 'work': return 'Focus'
      case 'shortBreak': return 'Short Break'
      case 'longBreak': return 'Long Break'
      default: return type
    }
  }

  const progress = status.totalSeconds > 0
    ? ((status.totalSeconds - status.remainingSeconds) / status.totalSeconds) * 100
    : 0

  const formatDuration = (minutes: number): string => {
    const hours = Math.floor(minutes / 60)
    const mins = minutes % 60
    if (hours > 0) return `${hours}h ${mins}m`
    return `${mins}m`
  }

  const handleOpenStats = () => {
    window.api.window.openStats()
  }

  const selectStyle = {
    background: 'var(--bg-card)',
    color: 'var(--text-primary)',
    border: '1px solid var(--border)',
    borderRadius: '6px',
    padding: '6px 10px',
    fontSize: '13px',
    width: '100%'
  }

  const inputStyle = {
    ...selectStyle,
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
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: '8px', flexShrink: 0 }}>
        <Button variant="ghost" size="sm" onClick={onBack}>← Back</Button>
        <span style={{ flex: 1, textAlign: 'center', fontWeight: 500 }}>
          {getSessionLabel(status.sessionType)}
        </span>
        <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
          #{todayStats.totalSessions}
        </span>
      </div>

      {/* Today Summary */}
      <div
        onClick={handleOpenStats}
        style={{
          display: 'flex',
          justifyContent: 'center',
          gap: '16px',
          padding: '8px',
          marginBottom: '8px',
          background: 'var(--bg-card)',
          borderRadius: '8px',
          cursor: 'pointer',
          flexShrink: 0
        }}
      >
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: '18px', fontWeight: 600 }}>{todayStats.totalSessions}</div>
          <div style={{ fontSize: '10px', color: 'var(--text-secondary)' }}>sessions</div>
        </div>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: '18px', fontWeight: 600 }}>{formatDuration(todayStats.totalMinutes)}</div>
          <div style={{ fontSize: '10px', color: 'var(--text-secondary)' }}>focused</div>
        </div>
      </div>

      {/* Timer Display */}
      <div style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: status.state === 'idle' ? 'flex-start' : 'center',
        overflowY: 'auto',
        paddingTop: status.state === 'idle' ? '8px' : '0'
      }}>
        {/* Progress Ring */}
        <div style={{ position: 'relative', width: '140px', height: '140px', marginBottom: '12px', flexShrink: 0 }}>
          <svg width="140" height="140" style={{ transform: 'rotate(-90deg)' }}>
            <circle
              cx="70" cy="70" r="62"
              fill="none"
              stroke="var(--bg-card)"
              strokeWidth="6"
            />
            <circle
              cx="70" cy="70" r="62"
              fill="none"
              stroke={status.sessionType === 'work' ? 'var(--accent)' : 'var(--success)'}
              strokeWidth="6"
              strokeLinecap="round"
              strokeDasharray={2 * Math.PI * 62}
              strokeDashoffset={2 * Math.PI * 62 * (1 - progress / 100)}
              style={{ transition: 'stroke-dashoffset 0.5s ease' }}
            />
          </svg>
          <div style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            textAlign: 'center'
          }}>
            <div style={{ fontSize: '32px', fontWeight: 600, fontFamily: 'monospace' }}>
              {status.state === 'idle' ? '--:--' : formatTime(status.remainingSeconds)}
            </div>
          </div>
        </div>

        {/* Current session info (running/paused) */}
        {(status.state === 'running' || status.state === 'paused') && status.sessionType === 'work' && (
          <div style={{ marginBottom: '12px', textAlign: 'center' }}>
            <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
              {selectedProject || 'No project'}
              {selectedTags.length > 0 && ` · ${selectedTags.join(', ')}`}
            </div>
            {taskDescription && (
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '4px', fontStyle: 'italic' }}>
                {taskDescription}
              </div>
            )}
            <Button variant="ghost" size="sm" onClick={() => setShowEditModal(true)}>
              Edit
            </Button>
          </div>
        )}

        {/* Project/Tag Summary + Expand (idle state) */}
        {status.state === 'idle' && !showIdleConfig && (
          <div
            onClick={() => setShowIdleConfig(true)}
            style={{
              padding: '8px 12px',
              background: 'var(--bg-card)',
              borderRadius: '8px',
              cursor: 'pointer',
              textAlign: 'center',
              marginBottom: '12px',
              maxWidth: '280px',
              width: '100%',
              flexShrink: 0
            }}
          >
            <div style={{ fontSize: '13px', color: 'var(--text-primary)' }}>
              {selectedProject || 'No project'}
              {selectedTags.length > 0 && (
                <span style={{ color: 'var(--text-secondary)' }}> · {selectedTags.join(', ')}</span>
              )}
            </div>
            {taskDescription && (
              <div style={{ fontSize: '11px', color: 'var(--text-secondary)', marginTop: '2px', fontStyle: 'italic' }}>
                {taskDescription}
              </div>
            )}
            <div style={{ fontSize: '10px', color: 'var(--text-secondary)', marginTop: '4px' }}>
              Tap to edit ▸
            </div>
          </div>
        )}

        {/* Project/Tag Editor (idle state, expanded) */}
        {status.state === 'idle' && showIdleConfig && (
          <div style={{ width: '100%', maxWidth: '280px', marginBottom: '12px', flexShrink: 1, minHeight: 0, overflowY: 'auto' }}>
            {/* Project */}
            <div style={{ marginBottom: '8px' }}>
              <label style={{ fontSize: '11px', color: 'var(--text-secondary)', display: 'block', marginBottom: '2px' }}>
                Project
              </label>
              <div style={{ display: 'flex', gap: '4px' }}>
                <select
                  value={selectedProject}
                  onChange={(e) => setSelectedProject(e.target.value)}
                  style={{ ...selectStyle, flex: 1, padding: '5px 8px', fontSize: '12px' }}
                >
                  <option value="">Select...</option>
                  {projects.map((p) => (
                    <option key={p} value={p}>{p}</option>
                  ))}
                </select>
                <input
                  type="text"
                  placeholder="New"
                  value={newProject}
                  onChange={(e) => setNewProject(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleAddProject()}
                  style={{ ...inputStyle, width: '60px', padding: '5px 8px', fontSize: '12px' }}
                />
              </div>
            </div>
            {/* Tags */}
            <div style={{ marginBottom: '8px' }}>
              <label style={{ fontSize: '11px', color: 'var(--text-secondary)', display: 'block', marginBottom: '2px' }}>
                Tags
              </label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px', marginBottom: '4px' }}>
                {tags.map((tag) => (
                  <span
                    key={tag}
                    onClick={() => handleToggleTag(tag)}
                    style={{ ...tagStyle(selectedTags.includes(tag)), padding: '2px 6px', fontSize: '11px' }}
                  >
                    {tag}
                  </span>
                ))}
              </div>
              <input
                type="text"
                placeholder="Add tag..."
                value={newTag}
                onChange={(e) => setNewTag(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleAddTag()}
                style={{ ...inputStyle, padding: '5px 8px', fontSize: '12px' }}
              />
            </div>
            {/* Task */}
            <div style={{ marginBottom: '8px' }}>
              <label style={{ fontSize: '11px', color: 'var(--text-secondary)', display: 'block', marginBottom: '2px' }}>
                Task (optional)
              </label>
              <input
                type="text"
                placeholder="What are you working on?"
                value={taskDescription}
                onChange={(e) => setTaskDescription(e.target.value)}
                style={{ ...inputStyle, padding: '5px 8px', fontSize: '12px' }}
              />
            </div>
            <div style={{ textAlign: 'center' }}>
              <Button variant="ghost" size="sm" onClick={() => setShowIdleConfig(false)}>
                ▴ Collapse
              </Button>
            </div>
          </div>
        )}

        {/* Controls */}
        <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap', justifyContent: 'center', flexShrink: 0, paddingBottom: '8px' }}>
          {status.state === 'idle' && (
            <Button onClick={handleStart}>Start Focus</Button>
          )}

          {status.state === 'running' && status.sessionType === 'work' && (
            <>
              <Button onClick={handlePause} variant="secondary">Pause</Button>
              <Button onClick={handleFinishEarly} variant="primary">Finish Early</Button>
              <Button onClick={handleExit} variant="ghost" size="sm">Exit</Button>
            </>
          )}

          {status.state === 'running' && status.sessionType !== 'work' && (
            <>
              <Button onClick={handleSkipBreak}>Skip</Button>
              <Button onClick={handleExit} variant="ghost" size="sm">Exit</Button>
            </>
          )}

          {status.state === 'paused' && status.sessionType === 'work' && (
            <>
              <Button onClick={handleResume}>Resume</Button>
              <Button onClick={handleFinishEarly} variant="primary">Finish Early</Button>
              <Button onClick={handleExit} variant="ghost" size="sm">Exit</Button>
            </>
          )}

          {status.state === 'paused' && status.sessionType !== 'work' && (
            <>
              <Button onClick={handleResume}>Resume</Button>
              <Button onClick={handleSkipBreak} variant="secondary">Skip</Button>
              <Button onClick={handleExit} variant="ghost" size="sm">Exit</Button>
            </>
          )}

          {status.state === 'finished' && nextOptions.length > 0 && (
            <>
              {nextOptions.map((option) => (
                <Button
                  key={option.action}
                  onClick={() => handleNextAction(option)}
                  variant={option.action === 'exit' ? 'ghost' : 'primary'}
                  size={option.action === 'exit' ? 'sm' : undefined}
                >
                  {option.label}
                </Button>
              ))}
            </>
          )}
        </div>
      </div>

      {/* Edit Modal */}
      {showEditModal && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.5)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 100
        }}>
          <div style={{
            background: 'var(--bg-primary)',
            borderRadius: '12px',
            padding: '20px',
            width: '280px',
            maxHeight: '80vh',
            overflowY: 'auto'
          }}>
            <h3 style={{ margin: '0 0 16px', fontSize: '16px' }}>Edit Session</h3>
            <div style={{ marginBottom: '12px' }}>
              <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
                Project
              </label>
              <div style={{ display: 'flex', gap: '6px' }}>
                <select
                  value={selectedProject}
                  onChange={(e) => setSelectedProject(e.target.value)}
                  style={{ ...selectStyle, flex: 1 }}
                >
                  <option value="">Select project...</option>
                  {projects.map((p) => (
                    <option key={p} value={p}>{p}</option>
                  ))}
                </select>
                <input
                  type="text"
                  placeholder="New"
                  value={newProject}
                  onChange={(e) => setNewProject(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleAddProject()}
                  style={{ ...inputStyle, width: '70px' }}
                />
              </div>
            </div>
            <div style={{ marginBottom: '12px' }}>
              <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
                Tags
              </label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginBottom: '6px', maxHeight: '120px', overflowY: 'auto' }}>
                {tags.map((tag) => (
                  <span
                    key={tag}
                    onClick={() => handleToggleTag(tag)}
                    style={tagStyle(selectedTags.includes(tag))}
                  >
                    {tag}
                  </span>
                ))}
              </div>
              <input
                type="text"
                placeholder="Add tag..."
                value={newTag}
                onChange={(e) => setNewTag(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleAddTag()}
                style={inputStyle}
              />
            </div>
            <div style={{ marginBottom: '16px' }}>
              <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
                Task
              </label>
              <input
                type="text"
                placeholder="What are you working on?"
                value={taskDescription}
                onChange={(e) => setTaskDescription(e.target.value)}
                style={inputStyle}
              />
            </div>
            <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
              <Button variant="ghost" onClick={() => setShowEditModal(false)}>Cancel</Button>
              <Button onClick={handleSaveEdit}>Save</Button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
