import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts'
import { getAppColor, formatDuration } from './appColors'

interface AppSummaryEntry {
  app: string
  duration: number
  percentage: number
}

interface AppUsageChartProps {
  data: AppSummaryEntry[]
  totalTime: number
}

const TOP_N = 5

export default function AppUsageChart({ data, totalTime }: AppUsageChartProps) {
  if (data.length === 0) {
    return (
      <div style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '40px' }}>
        No data available
      </div>
    )
  }

  // Take top N and group rest as "Other"
  const sortedData = [...data].sort((a, b) => b.duration - a.duration)
  const topApps = sortedData.slice(0, TOP_N)
  const otherApps = sortedData.slice(TOP_N)

  let chartData = topApps.map((entry) => ({
    name: entry.app,
    value: entry.duration,
    percentage: entry.percentage
  }))

  if (otherApps.length > 0) {
    const otherDuration = otherApps.reduce((sum, e) => sum + e.duration, 0)
    const otherPercentage = otherApps.reduce((sum, e) => sum + e.percentage, 0)
    chartData.push({
      name: 'Other',
      value: otherDuration,
      percentage: otherPercentage
    })
  }

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
      {/* Donut Chart */}
      <div style={{ width: '160px', height: '160px', position: 'relative' }}>
        <ResponsiveContainer>
          <PieChart>
            <Pie
              data={chartData}
              innerRadius={45}
              outerRadius={70}
              paddingAngle={2}
              dataKey="value"
            >
              {chartData.map((entry, index) => (
                <Cell
                  key={`cell-${index}`}
                  fill={entry.name === 'Other' ? '#6b7280' : getAppColor(entry.name)}
                />
              ))}
            </Pie>
            <Tooltip
              content={({ active, payload }) => {
                if (active && payload && payload.length) {
                  const data = payload[0].payload
                  return (
                    <div
                      style={{
                        background: 'var(--bg-primary)',
                        border: '1px solid var(--border)',
                        borderRadius: '6px',
                        padding: '8px 12px',
                        fontSize: '12px'
                      }}
                    >
                      <div style={{ fontWeight: 500 }}>{data.name}</div>
                      <div style={{ color: 'var(--text-secondary)' }}>
                        {formatDuration(data.value)} ({data.percentage.toFixed(1)}%)
                      </div>
                    </div>
                  )
                }
                return null
              }}
            />
          </PieChart>
        </ResponsiveContainer>
        {/* Center text */}
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            textAlign: 'center'
          }}
        >
          <div style={{ fontSize: '14px', fontWeight: 600 }}>{formatDuration(totalTime)}</div>
          <div style={{ fontSize: '10px', color: 'var(--text-secondary)' }}>Active</div>
        </div>
      </div>

      {/* Legend */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {chartData.map((entry) => (
          <div
            key={entry.name}
            style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '13px' }}
          >
            <div
              style={{
                width: '10px',
                height: '10px',
                borderRadius: '2px',
                background: entry.name === 'Other' ? '#6b7280' : getAppColor(entry.name),
                flexShrink: 0
              }}
            />
            <span
              style={{
                flex: 1,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap'
              }}
            >
              {entry.name}
            </span>
            <span style={{ color: 'var(--text-secondary)', flexShrink: 0 }}>
              {entry.percentage.toFixed(0)}%
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
