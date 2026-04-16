import { dataManager } from '../../core'
import type { SessionRecord, DailyStats, WeeklyStats, ActivityData, TimelineSegment } from '@shared/types'

export type { DailyStats, WeeklyStats, ActivityData, TimelineSegment }

class StatsService {
  private formatDate(date: Date): string {
    return date.toISOString().split('T')[0]
  }

  private formatTime(date: Date): string {
    return date.toTimeString().slice(0, 5)
  }

  /** Work sessions from active store only (recent data, fast) */
  private getWorkSessions(): SessionRecord[] {
    const stats = dataManager.getStats()
    return stats.history.filter((s) => s.type === 'work' && s.completionType !== 'skipped')
  }

  /** All sessions from active store only (recent data, fast) */
  private getAllSessions(): SessionRecord[] {
    return dataManager.getStats().history
  }

  /** Work sessions including archived (for long-range views like activity calendar) */
  private getAllWorkSessionsFull(): SessionRecord[] {
    return dataManager.getAllSessions().filter((s) => s.type === 'work' && s.completionType !== 'skipped')
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

    // Use full history (including archived) for long-range activity calendar
    const countMap = new Map<string, number>()
    for (const session of this.getAllWorkSessionsFull()) {
      const date = session.startTime.split('T')[0]
      countMap.set(date, (countMap.get(date) || 0) + 1)
    }

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
