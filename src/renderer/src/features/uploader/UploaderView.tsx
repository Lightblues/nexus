import { useState, useEffect, useCallback } from 'react'
import { Button } from '../../components'
import DropZone from './DropZone'
import ImagePreview from './ImagePreview'
import UploadHistory from './UploadHistory'
import type { UploaderConfig, UploadRecord } from '@shared/types'

interface ImageState {
  buffer: number[]
  filename: string
  format: string
  width: number
  height: number
  originalSize: number
  compressedBuffer?: number[]
  compressedSize?: number
  outputFormat?: string
}

interface UploaderViewProps {
  onBack: () => void
}

export default function UploaderView({ onBack }: UploaderViewProps) {
  const [config, setConfig] = useState<UploaderConfig | null>(null)
  const [image, setImage] = useState<ImageState | null>(null)
  const [path, setPath] = useState('')
  const [filename, setFilename] = useState('')
  const [recentPaths, setRecentPaths] = useState<string[]>([])
  const [history, setHistory] = useState<UploadRecord[]>([])
  const [quality, setQuality] = useState(80)
  const [outputFormat, setOutputFormat] = useState<'auto' | 'webp' | 'jpeg' | 'png'>('auto')
  const [uploading, setUploading] = useState(false)
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  const processImage = useCallback(async (buffer: number[], name: string, cfg: UploaderConfig | null) => {
    const meta = await window.api.uploader.getImageMeta(buffer)
    const baseName = name.replace(/\.[^/.]+$/, '')
    const ext = meta.format === 'jpeg' ? 'jpg' : meta.format

    setImage({
      buffer,
      filename: name,
      format: meta.format,
      width: meta.width,
      height: meta.height,
      originalSize: buffer.length
    })
    setFilename(`${baseName}.${ext}`)
    setMessage(null)
  }, [])

  // Separate effect to handle compression when quality/format changes
  useEffect(() => {
    if (!image?.buffer) return

    const performCompression = async () => {
      try {
        const result = await window.api.uploader.compress(image.buffer, quality, outputFormat)
        setImage((prev) => prev ? {
          ...prev,
          compressedBuffer: result.buffer,
          compressedSize: result.compressedSize,
          width: result.width,
          height: result.height,
          outputFormat: result.outputFormat
        } : null)
        // Update filename extension if format changed
        if (result.outputFormat && result.outputFormat !== image.format) {
          const baseName = filename.replace(/\.[^/.]+$/, '')
          const newExt = result.outputFormat === 'jpeg' ? 'jpg' : result.outputFormat
          setFilename(`${baseName}.${newExt}`)
        }
      } catch (err) {
        console.error('Compression failed:', err)
      }
    }

    performCompression()
  }, [image?.buffer, quality, outputFormat]) // Re-compress when quality or format changes

  const handleImageSelect = useCallback(async (buffer: number[], name: string) => {
    await processImage(buffer, name, config)
  }, [config, processImage])

  const loadData = useCallback(async () => {
    const [cfg, paths, hist, pendingImage] = await Promise.all([
      window.api.uploader.getConfig(),
      window.api.uploader.getRecentPaths(),
      window.api.uploader.getHistory(),
      window.api.uploader.getPendingImage()
    ])
    setConfig(cfg)
    setRecentPaths(paths)
    setHistory(hist)
    if (cfg) {
      setPath(cfg.defaultPath)
      setQuality(cfg.compress.quality)
      setOutputFormat(cfg.compress.defaultFormat)
    }

    // Process pending image if any (from tray drop)
    if (pendingImage) {
      await processImage(pendingImage.buffer, pendingImage.filename, cfg)
    }
  }, [processImage])

  useEffect(() => {
    loadData()
    // Listen for images dropped on tray icon (for when view is already mounted)
    const cleanupDropped = window.api.uploader.onImageDropped((data) => {
      // Process immediately if config is loaded
      if (config) {
        processImage(data.buffer, data.filename, config)
      }
    })
    return () => cleanupDropped()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const handleUpload = async () => {
    if (!image || !filename) return

    setUploading(true)
    setMessage(null)

    try {
      const bufferToUpload = image.compressedBuffer || image.buffer
      const result = await window.api.uploader.upload(
        bufferToUpload,
        filename,
        path,
        {
          width: image.width,
          height: image.height,
          format: image.format,
          originalSize: image.originalSize
        }
      )

      if (result.success && result.cdnUrl) {
        await window.api.uploader.copyUrl(result.cdnUrl)
        setMessage({ type: 'success', text: 'Uploaded! URL copied to clipboard' })
        setImage(null)
        setFilename('')
        // Refresh history
        const hist = await window.api.uploader.getHistory()
        setHistory(hist)
        const paths = await window.api.uploader.getRecentPaths()
        setRecentPaths(paths)
      } else {
        setMessage({ type: 'error', text: result.error || 'Upload failed' })
      }
    } catch (err) {
      setMessage({ type: 'error', text: err instanceof Error ? err.message : 'Upload failed' })
    } finally {
      setUploading(false)
    }
  }

  const handleCopyUrl = async (url: string) => {
    await window.api.uploader.copyUrl(url)
    setMessage({ type: 'success', text: 'URL copied!' })
    setTimeout(() => setMessage(null), 2000)
  }

  const isConfigured = config?.github.token && config?.github.owner && config?.github.repo

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '8px' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: '12px', flexShrink: 0 }}>
        <button
          onClick={onBack}
          style={{
            background: 'none',
            border: 'none',
            cursor: 'pointer',
            fontSize: '18px',
            padding: '4px 8px',
            marginRight: '8px',
            color: 'var(--text-primary)'
          }}
        >
          ←
        </button>
        <h2 style={{ fontSize: '16px', margin: 0 }}>🖼️ Image Uploader</h2>
      </div>

      {/* Scrollable Content */}
      <div style={{ flex: 1, overflow: 'auto', minHeight: 0 }}>
        {/* Not configured warning */}
        {!isConfigured && (
          <div style={{
            padding: '12px',
            background: 'var(--warning-bg)',
            borderRadius: '6px',
            fontSize: '12px',
            marginBottom: '12px'
          }}>
            ⚠️ Please configure GitHub token in Settings
          </div>
        )}

        {/* Drop Zone */}
        <DropZone onImageSelect={handleImageSelect} disabled={!isConfigured || uploading} />

        {/* Image Preview & Options */}
        {image && (
          <div style={{ marginTop: '12px' }}>
            <ImagePreview
              buffer={image.compressedBuffer || image.buffer}
              format={image.outputFormat || image.format}
              width={image.width}
              height={image.height}
              originalSize={image.originalSize}
              compressedSize={image.compressedSize}
            />

            {/* Compression Controls */}
            <div style={{ marginTop: '12px', padding: '12px', background: 'var(--bg-secondary)', borderRadius: '6px' }}>
              <div style={{ marginBottom: '8px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                  <label style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Quality</label>
                  <span style={{ fontSize: '12px', color: 'var(--text-primary)' }}>{quality}</span>
                </div>
                <input
                  type="range"
                  min="1"
                  max="100"
                  value={quality}
                  onChange={(e) => setQuality(Number(e.target.value))}
                  style={{ width: '100%' }}
                />
              </div>
              <div>
                <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
                  Format
                </label>
                <select
                  value={outputFormat}
                  onChange={(e) => setOutputFormat(e.target.value as 'auto' | 'webp' | 'jpeg' | 'png')}
                  style={{
                    width: '100%',
                    padding: '6px 8px',
                    fontSize: '12px',
                    border: '1px solid var(--border)',
                    borderRadius: '4px',
                    background: 'var(--bg-tertiary)',
                    color: 'var(--text-primary)'
                  }}
                >
                  <option value="auto">Auto (Smart)</option>
                  <option value="webp">WebP</option>
                  <option value="jpeg">JPEG</option>
                  <option value="png">PNG</option>
                </select>
              </div>
            </div>

            {/* Path & Filename */}
            <div style={{ marginTop: '12px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <div>
                <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
                  Path
                </label>
                <div style={{ display: 'flex', gap: '4px' }}>
                  <input
                    type="text"
                    value={path}
                    onChange={(e) => setPath(e.target.value)}
                    placeholder="upload"
                    list="recent-paths"
                    style={{
                      flex: 1,
                      padding: '6px 8px',
                      fontSize: '12px',
                      border: '1px solid var(--border)',
                      borderRadius: '4px',
                      background: 'var(--bg-secondary)',
                      color: 'var(--text-primary)'
                    }}
                  />
                  <datalist id="recent-paths">
                    {recentPaths.map((p) => (
                      <option key={p} value={p} />
                    ))}
                  </datalist>
                </div>
              </div>
              <div>
                <label style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'block', marginBottom: '4px' }}>
                  Filename
                </label>
                <input
                  type="text"
                  value={filename}
                  onChange={(e) => setFilename(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '6px 8px',
                    fontSize: '12px',
                    border: '1px solid var(--border)',
                    borderRadius: '4px',
                    background: 'var(--bg-secondary)',
                    color: 'var(--text-primary)'
                  }}
                />
              </div>
            </div>

            {/* Upload button */}
            <div style={{ marginTop: '12px', display: 'flex', justifyContent: 'flex-end' }}>
              <Button onClick={handleUpload} disabled={uploading || !filename}>
                {uploading ? 'Uploading...' : 'Upload'}
              </Button>
            </div>
          </div>
        )}

        {/* Message */}
        {message && (
          <div style={{
            marginTop: '12px',
            padding: '8px 12px',
            borderRadius: '6px',
            fontSize: '12px',
            background: message.type === 'success' ? 'var(--success-bg)' : 'var(--error-bg)',
            color: message.type === 'success' ? 'var(--success)' : 'var(--error)',
            flexShrink: 0
          }}>
            {message.text}
          </div>
        )}

        {/* History */}
        <div style={{ marginTop: '16px', paddingTop: '12px', borderTop: '1px solid var(--border)' }}>
          <div style={{
            fontSize: '12px',
            fontWeight: 500,
            marginBottom: '8px',
            color: 'var(--text-secondary)'
          }}>
            Recent Uploads
          </div>
          <UploadHistory history={history} onCopy={handleCopyUrl} />
        </div>
      </div>
    </div>
  )
}
