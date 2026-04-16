import { useState, useEffect } from 'react'
import { Card } from '../../components'
import ActivityCalendar from './ActivityCalendar'
import WeeklyChart from './WeeklyChart'
import DailyTimeline from './DailyTimeline'
import SessionList from './SessionList'
import SessionEditModal from './SessionEditModal'
import type { WeeklyStats, ActivityData, TimelineSegment, SessionRecord } from '@shared/types'

export default function StatsView() {
  const [weeklyStats, setWeeklyStats] = useState<WeeklyStats | null>(null)
  const [activityData, setActivityData] = useState<ActivityData[]>([])
  const [timelineData, setTimelineData] = useState<TimelineSegment[]>([])
  const [sessions, setSessions] = useState<SessionRecord[]>([])
  const [selectedDate, setSelectedDate] = useState<string>(new Date().toISOString().split('T')[0])
  const [loading, setLoading] = useState(true)
  const [editingSession, setEditingSession] = useState<SessionRecord | null>(null)
  const [projects, setProjects] = useState<string[]>([])
  const [tags, setTags] = useState<string[]>([])

  const loadDateData = async (date: string) => {
    const [timeline, sessionList] = await Promise.all([
      window.api.stats.getTimeline(date),
      window.api.stats.getSessions(date)
    ])
    setTimelineData(timeline)
    setSessions(sessionList)
  }

  useEffect(() => {
    const loadData = async () => {
      setLoading(true)
      try {
        const [weekly, activity, timeline, sessionList, projectList, tagList] = await Promise.all([
          window.api.stats.getWeekly(),
          window.api.stats.getActivity(6),
          window.api.stats.getTimeline(selectedDate),
          window.api.stats.getSessions(selectedDate),
          window.api.pomodoro.getProjects(),
          window.api.pomodoro.getTags()
        ])
        setWeeklyStats(weekly)
        setActivityData(activity)
        setTimelineData(timeline)
        setSessions(sessionList)
        setProjects(projectList)
        setTags(tagList)
      } catch (err) {
        console.error('Failed to load stats:', err)
      }
      setLoading(false)
    }
    loadData()
  }, [])

  useEffect(() => {
    loadDateData(selectedDate)
  }, [selectedDate])

  const handleEditSession = (session: SessionRecord) => {
    setEditingSession(session)
  }

  const handleSaveSession = async (id: string, updates: Record<string, unknown>) => {
    await window.api.stats.updateSession(id, updates)
    setEditingSession(null)
    // Refresh data
    await loadDateData(selectedDate)
    // Refresh weekly stats if needed
    const weekly = await window.api.stats.getWeekly()
    setWeeklyStats(weekly)
    // Refresh projects/tags in case new ones were added
    const [projectList, tagList] = await Promise.all([
      window.api.pomodoro.getProjects(),
      window.api.pomodoro.getTags()
    ])
    setProjects(projectList)
    setTags(tagList)
  }

  const handleCancelEdit = () => {
    setEditingSession(null)
  }

  const formatDuration = (minutes: number): string => {
    const hours = Math.floor(minutes / 60)
    const mins = minutes % 60
    if (hours > 0) return `${hours}h ${mins}m`
    return `${mins}m`
  }

  if (loading) {
    return (
      <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)' }}>
        Loading statistics...
      </div>
    )
  }

  return (
    <div style={{ padding: '24px', height: '100%', overflow: 'auto' }}>
      <h1 style={{ fontSize: '24px', marginBottom: '24px' }}>Focus Statistics</h1>

      {/* Summary Cards */}
      {weeklyStats && (
        <div style={{ display: 'flex', gap: '16px', marginBottom: '24px' }}>
          <Card style={{ flex: 1, padding: '16px', textAlign: 'center' }}>
            <div style={{ fontSize: '32px', fontWeight: 600 }}>{weeklyStats.totalSessions}</div>
            <div style={{ fontSize: '14px', color: 'var(--text-secondary)' }}>sessions this week</div>
          </Card>
          <Card style={{ flex: 1, padding: '16px', textAlign: 'center' }}>
            <div style={{ fontSize: '32px', fontWeight: 600 }}>{formatDuration(weeklyStats.totalMinutes)}</div>
            <div style={{ fontSize: '14px', color: 'var(--text-secondary)' }}>focused this week</div>
          </Card>
        </div>
      )}

      {/* Activity Calendar */}
      <Card style={{ padding: '16px', marginBottom: '24px' }}>
        <h2 style={{ fontSize: '16px', marginBottom: '16px' }}>Activity</h2>
        <ActivityCalendar data={activityData} />
      </Card>

      {/* Weekly Chart */}
      {weeklyStats && (
        <Card style={{ padding: '16px', marginBottom: '24px' }}>
          <h2 style={{ fontSize: '16px', marginBottom: '16px' }}>This Week</h2>
          <WeeklyChart data={weeklyStats.days} />
        </Card>
      )}

      {/* Daily Timeline */}
      <Card style={{ padding: '16px', marginBottom: '24px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
          <h2 style={{ fontSize: '16px', margin: 0 }}>Daily Timeline</h2>
          <input
            type="date"
            value={selectedDate}
            onChange={(e) => setSelectedDate(e.target.value)}
            style={{
              background: 'var(--bg-card)',
              color: 'var(--text-primary)',
              border: '1px solid var(--border)',
              borderRadius: '4px',
              padding: '4px 8px',
              fontSize: '13px'
            }}
          />
        </div>
        <DailyTimeline data={timelineData} />
      </Card>

      {/* Session List */}
      <Card style={{ padding: '16px' }}>
        <SessionList sessions={sessions} onEdit={handleEditSession} />
      </Card>

      {/* Edit Modal */}
      {editingSession && (
        <SessionEditModal
          session={editingSession}
          projects={projects}
          tags={tags}
          onSave={handleSaveSession}
          onCancel={handleCancelEdit}
        />
      )}
    </div>
  )
}
