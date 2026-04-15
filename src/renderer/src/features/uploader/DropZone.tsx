import { useState, useCallback, useRef } from 'react'

interface DropZoneProps {
  onImageSelect: (buffer: number[], filename: string) => void
  disabled?: boolean
}

export default function DropZone({ onImageSelect, disabled }: DropZoneProps) {
  const [isDragging, setIsDragging] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    if (!disabled) setIsDragging(true)
  }, [disabled])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setIsDragging(false)
  }, [])

  const handleDrop = useCallback(async (e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setIsDragging(false)
    if (disabled) return

    const files = e.dataTransfer.files
    if (files.length > 0) {
      const file = files[0]
      if (file.type.startsWith('image/')) {
        const buffer = await file.arrayBuffer()
        onImageSelect(Array.from(new Uint8Array(buffer)), file.name)
      }
    }
  }, [disabled, onImageSelect])

  const handlePaste = useCallback(async () => {
    if (disabled) return
    const image = await window.api.uploader.getClipboardImage()
    if (image) {
      const timestamp = new Date().toISOString().slice(0, 10)
      const filename = `screenshot-${timestamp}.${image.format}`
      onImageSelect(image.buffer, filename)
    }
  }, [disabled, onImageSelect])

  const handleFileSelect = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file && file.type.startsWith('image/')) {
      const buffer = await file.arrayBuffer()
      onImageSelect(Array.from(new Uint8Array(buffer)), file.name)
    }
    // Reset input
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }, [onImageSelect])

  const handleClick = () => {
    if (!disabled) {
      fileInputRef.current?.click()
    }
  }

  return (
    <div
      onClick={handleClick}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
      style={{
        padding: '24px 16px',
        textAlign: 'center',
        cursor: disabled ? 'not-allowed' : 'pointer',
        border: isDragging ? '2px dashed var(--accent)' : '2px dashed var(--border)',
        background: isDragging ? 'var(--bg-hover)' : 'var(--bg-card)',
        borderRadius: 'var(--radius)',
        opacity: disabled ? 0.5 : 1,
        transition: 'all 0.2s'
      }}
    >
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        onChange={handleFileSelect}
        style={{ display: 'none' }}
      />
      <div style={{ fontSize: '32px', marginBottom: '8px' }}>🖼️</div>
      <div style={{ fontSize: '14px', fontWeight: 500, marginBottom: '4px', color: 'var(--text-primary)' }}>
        Drop or Click to Select
      </div>
      <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
        or{' '}
        <span
          onClick={(e) => { e.stopPropagation(); handlePaste() }}
          style={{ color: 'var(--accent)', cursor: 'pointer', textDecoration: 'underline' }}
        >
          paste from clipboard
        </span>
      </div>
      <div style={{ fontSize: '10px', color: 'var(--text-secondary)', marginTop: '8px' }}>
        💡 Tip: Drag image to menubar icon for quick upload
      </div>
    </div>
  )
}
