import { dataManager, type SessionRecord } from '../../core'

export interface DailyStats {
  date: string
  totalSessions: number
  totalMinutes: number
  sessions: SessionRecord[]
}

export interface WeeklyStats {
  days: DailyStats[]
  totalSessions: number
  totalMinutes: number
}

export interface ActivityData {
  date: string
  count: number
  level: 0 | 1 | 2 | 3 | 4
}

export interface TimelineSegment {
  startTime: string
  endTime: string
  type: 'work' | 'shortBreak' | 'longBreak'
  duration: number
  project?: string
}

class StatsService {
  private formatDate(date: Date): string {
    return date.toISOString().split('T')[0]
  }

  private formatTime(date: Date): string {
    return date.toTimeString().slice(0, 5)
  }

  private getWorkSessions(): SessionRecord[] {
    const stats = dataManager.getStats()
    return stats.history.filter((s) => s.type === 'work' && s.completionType !== 'skipped')
  }

  private getAllSessions(): SessionRecord[] {
    return dataManager.getStats().history
  }

  private getSessionsForDate(date: string): SessionRecord[] {
    return this.getAllSessions().filter((s) => s.startTime.startsWith(date))
  }

  private getWorkSessionsForDate(date: string): SessionRecord[] {
    return this.getWorkSessions().filter((s) => s.startTime.startsWith(date))
  }

  private calculateLevel(count: number): 0 | 1 | 2 | 3 | 4 {
    if (count === 0) return 0
    if (count <= 2) return 1
    if (count <= 4) return 2
    if (count <= 6) return 3
    return 4
  }

  getTodayStats(): DailyStats {
    const today = this.formatDate(new Date())
    const sessions = this.getWorkSessionsForDate(today)
    return {
      date: today,
      totalSessions: sessions.length,
      totalMinutes: sessions.reduce((sum, s) => sum + s.duration, 0),
      sessions
    }
  }

  getWeeklyStats(): WeeklyStats {
    const days: DailyStats[] = []
    const now = new Date()

    for (let i = 6; i >= 0; i--) {
      const date = new Date(now)
      date.setDate(date.getDate() - i)
      const dateStr = this.formatDate(date)
      const sessions = this.getWorkSessionsForDate(dateStr)
      days.push({
        date: dateStr,
        totalSessions: sessions.length,
        totalMinutes: sessions.reduce((sum, s) => sum + s.duration, 0),
        sessions
      })
    }

    return {
      days,
      totalSessions: days.reduce((sum, d) => sum + d.totalSessions, 0),
      totalMinutes: days.reduce((sum, d) => sum + d.totalMinutes, 0)
    }
  }

  getActivityData(months: number = 6): ActivityData[] {
    const result: ActivityData[] = []
    const now = new Date()
    const startDate = new Date(now)
    startDate.setMonth(startDate.getMonth() - months)

    // Build a map of date -> session count
    const countMap = new Map<string, number>()
    for (const session of this.getWorkSessions()) {
      const date = session.startTime.split('T')[0]
      countMap.set(date, (countMap.get(date) || 0) + 1)
    }

    // Generate all dates in range
    const current = new Date(startDate)
    while (current <= now) {
      const dateStr = this.formatDate(current)
      const count = countMap.get(dateStr) || 0
      result.push({
        date: dateStr,
        count,
        level: this.calculateLevel(count)
      })
      current.setDate(current.getDate() + 1)
    }

    return result
  }

  getTimelineData(date?: string): TimelineSegment[] {
    const targetDate = date || this.formatDate(new Date())
    const sessions = this.getSessionsForDate(targetDate)

    return sessions
      .map((s) => ({
        startTime: this.formatTime(new Date(s.startTime)),
        endTime: this.formatTime(new Date(s.endTime)),
        type: s.type,
        duration: s.duration,
        project: s.project
      }))
      .sort((a, b) => a.startTime.localeCompare(b.startTime))
  }

  getSessionsForDateFull(date?: string): SessionRecord[] {
    const targetDate = date || this.formatDate(new Date())
    return this.getSessionsForDate(targetDate).sort(
      (a, b) => new Date(a.startTime).getTime() - new Date(b.startTime).getTime()
    )
  }

  updateSession(id: string, updates: Partial<Pick<SessionRecord, 'startTime' | 'endTime' | 'project' | 'tags' | 'task'>>): SessionRecord | null {
    return dataManager.updateSession(id, updates)
  }
}

export const statsService = new StatsService()
