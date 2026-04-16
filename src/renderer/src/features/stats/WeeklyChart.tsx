import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts'
import type { DailyStats } from '@shared/types'

interface WeeklyChartProps {
  data: DailyStats[]
}

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

export default function WeeklyChart({ data }: WeeklyChartProps) {
  const chartData = data.map((day) => {
    const date = new Date(day.date)
    return {
      name: DAY_NAMES[date.getDay()],
      hours: Math.round((day.totalMinutes / 60) * 10) / 10,
      minutes: day.totalMinutes,
      sessions: day.totalSessions,
      date: day.date
    }
  })

  const formatTooltip = (value: number, _name: string, props: { payload: { minutes: number; sessions: number } }) => {
    const { minutes, sessions } = props.payload
    const hours = Math.floor(minutes / 60)
    const mins = minutes % 60
    const timeStr = hours > 0 ? `${hours}h ${mins}m` : `${mins}m`
    return [`${timeStr} (${sessions} sessions)`, 'Focus time']
  }

  if (data.every((d) => d.totalMinutes === 0)) {
    return (
      <div style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '20px' }}>
        No focus data this week yet.
      </div>
    )
  }

  return (
    <ResponsiveContainer width="100%" height={200}>
      <BarChart data={chartData} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
        <XAxis
          dataKey="name"
          tick={{ fill: 'var(--text-secondary)', fontSize: 12 }}
          axisLine={{ stroke: 'var(--border)' }}
          tickLine={false}
        />
        <YAxis
          tick={{ fill: 'var(--text-secondary)', fontSize: 12 }}
          axisLine={false}
          tickLine={false}
          tickFormatter={(value) => `${value}h`}
        />
        <Tooltip
          formatter={formatTooltip}
          contentStyle={{
            background: 'var(--bg-primary)',
            border: '1px solid var(--border)',
            borderRadius: '8px',
            fontSize: '13px',
            color: 'var(--text-primary)'
          }}
          labelStyle={{ color: 'var(--text-primary)' }}
          itemStyle={{ color: 'var(--text-secondary)' }}
          cursor={{ fill: 'var(--bg-card)' }}
        />
        <Bar dataKey="hours" radius={[4, 4, 0, 0]}>
          {chartData.map((entry, index) => (
            <Cell
              key={`cell-${index}`}
              fill={entry.hours > 0 ? 'var(--accent)' : 'var(--bg-card)'}
            />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}
