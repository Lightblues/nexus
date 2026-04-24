import { useState, useEffect } from 'react'
import { Card } from '../../components'
import TrackerTimeline from './TrackerTimeline'
import AppUsageChart from './AppUsageChart'
import AppRankList from './AppRankList'
import type { ActivityContext, DailyTrackerData, TrackerStatus } from '@shared/types'

interface TrackerTimelineSegment {
  startTime: string
  endTime: string
  app: string
  duration: number
  context?: ActivityContext
}

interface AppSummaryEntryLocal {
  app: string
  duration: number
  percentage: number
  contexts?: { name: string; duration: number }[]
}

function transformToTimelineSegments(data: DailyTrackerData): TrackerTimelineSegment[] {
  return data.records.map((r) => ({
    startTime: new Date(r.startTime).toTimeString().slice(0, 5),
    endTime: new Date(r.endTime).toTimeString().slice(0, 5),
    app: r.app,
    duration: r.duration,
    context: r.context
  }))
}

function transformToAppSummary(data: DailyTrackerData): AppSummaryEntryLocal[] {
  const total = data.meta.totalActiveTime || 1
  const entries = Object.entries(data.meta.appSummary)
    .map(([app, duration]) => ({
      app,
      duration,
      percentage: (duration / total) * 100
    }))
    .sort((a, b) => b.duration - a.duration)

  // Build context breakdown per app
  const contextMap: Record<string, Record<string, number>> = {}
  for (const record of data.records) {
    const app = record.app
    if (!contextMap[app]) contextMap[app] = {}
    // Use project, domain, or file as context key
    const ctxKey =
      record.context?.project || record.context?.domain || record.context?.file || 'Unknown'
    contextMap[app][ctxKey] = (contextMap[app][ctxKey] || 0) + record.duration
  }

  return entries.map((entry) => {
    const ctxs = contextMap[entry.app]
    const contexts = ctxs
      ? Object.entries(ctxs)
          .map(([name, duration]) => ({ name, duration }))
          .sort((a, b) => b.duration - a.duration)
      : undefined
    return { ...entry, contexts }
  })
}

export default function TrackerView() {
  const [selectedDate, setSelectedDate] = useState<string>(new Date().toISOString().split('T')[0])
  const [data, setData] = useState<DailyTrackerData | null>(null)
  const [status, setStatus] = useState<TrackerStatus | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const loadData = async () => {
      setLoading(true)
      try {
        const [dayData, trackerStatus] = await Promise.all([
          window.api.tracker.getDay(selectedDate),
          window.api.tracker.getStatus()
        ])
        setData(dayData)
        setStatus(trackerStatus)
      } catch (err) {
        console.error('Failed to load tracker data:', err)
        setData(null)
      }
      setLoading(false)
    }
    loadData()
  }, [selectedDate])

  const timelineData = data ? transformToTimelineSegments(data) : []
  const appSummary = data ? transformToAppSummary(data) : []
  const totalTime = data?.meta.totalActiveTime || 0

  if (loading) {
    return (
      <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)' }}>
        Loading tracker data...
      </div>
    )
  }

  return (
    <div style={{ padding: '24px', height: '100%', overflow: 'auto' }}>
      {/* Header */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          marginBottom: '24px'
        }}
      >
        <h1 style={{ fontSize: '24px', margin: 0 }}>Time Tracker</h1>
        <input
          type="date"
          value={selectedDate}
          onChange={(e) => setSelectedDate(e.target.value)}
          style={{
            background: 'var(--bg-card)',
            color: 'var(--text-primary)',
            border: '1px solid var(--border)',
            borderRadius: '4px',
            padding: '6px 10px',
            fontSize: '13px'
          }}
        />
      </div>

      {/* Permission Warning */}
      {status && !status.permissionGranted && (
        <Card
          style={{
            padding: '16px',
            marginBottom: '24px',
            background: 'var(--warning-bg, #fef3c7)',
            border: '1px solid var(--warning-border, #f59e0b)'
          }}
        >
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
            <span style={{ fontSize: '20px' }}>⚠️</span>
            <div>
              <div style={{ fontWeight: 600, marginBottom: '4px', color: 'var(--warning-text, #92400e)' }}>
                Accessibility Permission Required
              </div>
              <div style={{ fontSize: '13px', color: 'var(--warning-text, #92400e)', opacity: 0.9 }}>
                Time Tracker needs Accessibility permission to monitor active windows.
                Go to System Settings → Privacy & Security → Accessibility, enable Nexus, then restart the app.
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* Timeline Card */}
      <Card style={{ padding: '16px', marginBottom: '24px' }}>
        <h2 style={{ fontSize: '16px', marginBottom: '16px' }}>Today&apos;s Activity</h2>
        <TrackerTimeline data={timelineData} />
      </Card>

      {/* Bottom Row: Donut Chart + Rank List */}
      <div style={{ display: 'flex', gap: '16px' }}>
        {/* Donut Chart */}
        <Card style={{ flex: 1, padding: '16px', minWidth: 0 }}>
          <h2 style={{ fontSize: '16px', marginBottom: '16px' }}>Usage Overview</h2>
          <AppUsageChart data={appSummary} totalTime={totalTime} />
        </Card>

        {/* Rank List */}
        <Card style={{ flex: 1, padding: '16px', minWidth: 0, maxHeight: '360px', overflow: 'auto' }}>
          <h2 style={{ fontSize: '16px', marginBottom: '16px' }}>App Ranking</h2>
          <AppRankList data={appSummary} />
        </Card>
      </div>
    </div>
  )
}
