import { ActivityCalendar as ActivityCalendarLib, ThemeInput } from 'react-activity-calendar'
import type { ActivityData } from '@shared/types'

interface ActivityCalendarProps {
  data: ActivityData[]
}

const theme: ThemeInput = {
  light: ['#ebedf0', '#9be9a8', '#40c463', '#30a14e', '#216e39'],
  dark: ['#161b22', '#0e4429', '#006d32', '#26a641', '#39d353']
}

export default function ActivityCalendar({ data }: ActivityCalendarProps) {
  if (data.length === 0) {
    return (
      <div style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '20px' }}>
        No activity data yet. Start a focus session to track your progress!
      </div>
    )
  }

  return (
    <div style={{ overflowX: 'auto' }}>
      <ActivityCalendarLib
        data={data}
        theme={theme}
        colorScheme="dark"
        blockSize={12}
        blockMargin={3}
        fontSize={12}
        labels={{
          totalCount: '{{count}} focus sessions in the last 6 months'
        }}
      />
    </div>
  )
}
