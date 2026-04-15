/** Predefined colors for common apps */
const APP_COLORS: Record<string, string> = {
  Code: '#007ACC',
  'Visual Studio Code': '#007ACC',
  'Google Chrome': '#4285F4',
  Chrome: '#4285F4',
  Safari: '#006CFF',
  Firefox: '#FF7139',
  Terminal: '#000000',
  iTerm2: '#000000',
  Slack: '#4A154B',
  Finder: '#1C9BEF',
  Notes: '#FFCC00',
  'Microsoft Word': '#2B579A',
  'Microsoft Excel': '#217346',
  'Microsoft PowerPoint': '#B7472A',
  Notion: '#000000',
  Figma: '#F24E1E',
  Discord: '#5865F2',
  Spotify: '#1DB954',
  Telegram: '#0088cc',
  WeChat: '#07C160',
  Zoom: '#2D8CFF',
  Arc: '#FCBFBD'
}

/** Generate color from string hash */
function hashToColor(str: string): string {
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash)
  }
  const hue = Math.abs(hash) % 360
  return `hsl(${hue}, 65%, 50%)`
}

/** Get color for an app */
export function getAppColor(app: string): string {
  return APP_COLORS[app] || hashToColor(app)
}

/** Format duration in seconds to human readable */
export function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  if (hours > 0) return `${hours}h ${mins}m`
  if (mins > 0) return `${mins}m`
  return `${seconds}s`
}
