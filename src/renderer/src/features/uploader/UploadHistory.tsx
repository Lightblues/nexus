import { useMemo, useEffect, useState } from 'react'
import type { UploadRecord } from '@shared/types'

interface UploadHistoryProps {
  history: UploadRecord[]
  onCopy: (url: string) => void
  onDelete?: (id: string) => void
}

function formatTimeAgo(timestamp: string): string {
  const diff = Date.now() - new Date(timestamp).getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

function ThumbnailImage({ id }: { id: string }) {
  const [thumbnailUrl, setThumbnailUrl] = useState<string | null>(null)

  useEffect(() => {
    window.api.uploader.getThumbnail(id).then((thumbnail) => {
      if (thumbnail) {
        const blob = new Blob([new Uint8Array(thumbnail)], { type: 'image/webp' })
        setThumbnailUrl(URL.createObjectURL(blob))
      }
    })
  }, [id])

  if (!thumbnailUrl) {
    return <div style={{ fontSize: '16px' }}>🖼️</div>
  }

  return (
    <img
      src={thumbnailUrl}
      alt="Thumbnail"
      style={{
        width: '100%',
        height: '100%',
        objectFit: 'cover'
      }}
    />
  )
}

export default function UploadHistory({ history, onCopy, onDelete }: UploadHistoryProps) {
  const recentItems = useMemo(() => history.slice(0, 5), [history])

  if (recentItems.length === 0) {
    return (
      <div style={{ fontSize: '12px', color: 'var(--text-secondary)', textAlign: 'center', padding: '12px' }}>
        No uploads yet
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
      {recentItems.map((item) => (
        <div
          key={item.id}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '8px',
            padding: '8px',
            background: 'var(--bg-secondary)',
            borderRadius: '6px',
            fontSize: '12px'
          }}
        >
          <div
            style={{
              width: '32px',
              height: '32px',
              borderRadius: '4px',
              background: 'var(--bg-tertiary)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: '16px',
              flexShrink: 0,
              overflow: 'hidden'
            }}
          >
            <ThumbnailImage id={item.id} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{
              fontWeight: 500,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis'
            }}>
              {item.filename}
            </div>
            <div style={{
              color: 'var(--text-secondary)',
              fontSize: '10px',
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis'
            }}>
              {item.path || 'root'}
            </div>
          </div>
          <div style={{ color: 'var(--text-secondary)', fontSize: '10px', flexShrink: 0 }}>
            {formatTimeAgo(item.timestamp)}
          </div>
          <button
            onClick={() => onCopy(item.cdnUrl)}
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: '4px',
              fontSize: '14px',
              opacity: 0.7
            }}
            title="Copy URL"
          >
            📋
          </button>
        </div>
      ))}
    </div>
  )
}
