import { useMemo, useState } from 'react'

interface ImagePreviewProps {
  buffer: number[]
  format: string
  width: number
  height: number
  originalSize: number
  compressedSize?: number
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`
}

export default function ImagePreview({
  buffer,
  format,
  width,
  height,
  originalSize,
  compressedSize
}: ImagePreviewProps) {
  const [showFullSize, setShowFullSize] = useState(false)

  const imageUrl = useMemo(() => {
    const blob = new Blob([new Uint8Array(buffer)], { type: `image/${format}` })
    return URL.createObjectURL(blob)
  }, [buffer, format])

  const savings = compressedSize
    ? Math.round(((originalSize - compressedSize) / originalSize) * 100)
    : 0

  return (
    <>
      <div style={{ display: 'flex', gap: '12px', alignItems: 'flex-start' }}>
        <div
          onClick={() => setShowFullSize(true)}
          style={{
            width: '80px',
            height: '80px',
            borderRadius: '8px',
            overflow: 'hidden',
            background: 'var(--bg-secondary)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
            cursor: 'pointer',
            position: 'relative'
          }}
          title="Click to view full size"
        >
          <img
            src={imageUrl}
            alt="Preview"
            style={{
              maxWidth: '100%',
              maxHeight: '100%',
              objectFit: 'contain'
            }}
          />
          <div style={{
            position: 'absolute',
            bottom: '4px',
            right: '4px',
            background: 'rgba(0,0,0,0.6)',
            borderRadius: '4px',
            padding: '2px 4px',
            fontSize: '10px'
          }}>
            🔍
          </div>
        </div>
      <div style={{ flex: 1, fontSize: '12px' }}>
        <div style={{ marginBottom: '4px' }}>
          <span style={{ color: 'var(--text-secondary)' }}>Dimensions: </span>
          <span>{width} × {height}</span>
        </div>
        <div style={{ marginBottom: '4px' }}>
          <span style={{ color: 'var(--text-secondary)' }}>Format: </span>
          <span style={{ textTransform: 'uppercase' }}>{format}</span>
        </div>
        <div>
          <span style={{ color: 'var(--text-secondary)' }}>Size: </span>
          <span>{formatBytes(originalSize)}</span>
          {compressedSize && compressedSize < originalSize && (
            <>
              <span style={{ color: 'var(--text-secondary)' }}> → </span>
              <span style={{ color: 'var(--success)' }}>{formatBytes(compressedSize)}</span>
              <span style={{ color: 'var(--success)', marginLeft: '4px' }}>
                ({savings}% ↓)
              </span>
            </>
          )}
        </div>
      </div>
      </div>

      {/* Full Size Modal */}
      {showFullSize && (
        <div
          onClick={() => setShowFullSize(false)}
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            background: 'rgba(0, 0, 0, 0.9)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
            cursor: 'pointer'
          }}
        >
          <img
            src={imageUrl}
            alt="Full size preview"
            style={{
              maxWidth: '90%',
              maxHeight: '90%',
              objectFit: 'contain'
            }}
          />
          <div style={{
            position: 'absolute',
            top: '16px',
            right: '16px',
            color: 'white',
            fontSize: '24px',
            cursor: 'pointer'
          }}>
            ✕
          </div>
        </div>
      )}
    </>
  )
}
