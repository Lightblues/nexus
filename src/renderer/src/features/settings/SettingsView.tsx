import { useState, useEffect, useRef } from 'react'
import Editor, { OnMount } from '@monaco-editor/react'
import { Button } from '../../components'

type Status = 'loading' | 'saved' | 'unsaved' | 'saving' | 'error'

export default function SettingsView() {
  const [content, setContent] = useState('')
  const [originalContent, setOriginalContent] = useState('')
  const [status, setStatus] = useState<Status>('loading')
  const [error, setError] = useState<string | null>(null)
  const editorRef = useRef<unknown>(null)

  useEffect(() => {
    loadConfig()
  }, [])

  const loadConfig = async () => {
    setStatus('loading')
    setError(null)
    try {
      const raw = await window.api.config.readRaw()
      setContent(raw)
      setOriginalContent(raw)
      setStatus('saved')
    } catch (err) {
      setError(`Failed to load config: ${(err as Error).message}`)
      setStatus('error')
    }
  }

  const handleEditorMount: OnMount = (editor) => {
    editorRef.current = editor
  }

  const handleEditorChange = (value: string | undefined) => {
    const newContent = value || ''
    setContent(newContent)
    setStatus(newContent === originalContent ? 'saved' : 'unsaved')
    setError(null)
  }

  const handleSave = async () => {
    setStatus('saving')
    setError(null)
    try {
      const result = await window.api.config.writeRaw(content)
      if (result.success) {
        setOriginalContent(content)
        setStatus('saved')
      } else {
        setError(result.error || 'Unknown error')
        setStatus('error')
      }
    } catch (err) {
      setError(`Save failed: ${(err as Error).message}`)
      setStatus('error')
    }
  }

  const handleReset = () => {
    setContent(originalContent)
    setStatus('saved')
    setError(null)
  }

  const getStatusText = () => {
    switch (status) {
      case 'loading': return 'Loading...'
      case 'saved': return 'Saved'
      case 'unsaved': return 'Unsaved changes'
      case 'saving': return 'Saving...'
      case 'error': return 'Error'
    }
  }

  const getStatusColor = () => {
    switch (status) {
      case 'saved': return 'var(--accent)'
      case 'unsaved': return '#f59e0b'
      case 'error': return '#ef4444'
      default: return 'var(--text-secondary)'
    }
  }

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', padding: '16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
        <div>
          <h1 style={{ fontSize: '24px', margin: 0 }}>Settings</h1>
          <p style={{ fontSize: '13px', color: 'var(--text-secondary)', margin: '4px 0 0 0' }}>
            Edit config.yaml directly
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <span style={{ fontSize: '13px', color: getStatusColor() }}>
            {getStatusText()}
          </span>
          <Button
            onClick={handleReset}
            disabled={status === 'loading' || status === 'saving' || status === 'saved'}
            style={{ opacity: status === 'saved' ? 0.5 : 1 }}
          >
            Reset
          </Button>
          <Button
            onClick={handleSave}
            disabled={status === 'loading' || status === 'saving' || status === 'saved'}
            style={{
              background: status === 'unsaved' ? 'var(--accent)' : undefined,
              color: status === 'unsaved' ? 'white' : undefined
            }}
          >
            Save
          </Button>
        </div>
      </div>

      {error && (
        <div style={{
          padding: '12px',
          marginBottom: '12px',
          background: 'rgba(239, 68, 68, 0.1)',
          border: '1px solid rgba(239, 68, 68, 0.3)',
          borderRadius: '6px',
          color: '#ef4444',
          fontSize: '13px',
          fontFamily: 'monospace',
          whiteSpace: 'pre-wrap'
        }}>
          {error}
        </div>
      )}

      <div style={{ flex: 1, border: '1px solid var(--border)', borderRadius: '6px', overflow: 'hidden' }}>
        {status === 'loading' ? (
          <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)' }}>
            Loading configuration...
          </div>
        ) : (
          <Editor
            height="100%"
            defaultLanguage="yaml"
            value={content}
            onChange={handleEditorChange}
            onMount={handleEditorMount}
            theme="vs-dark"
            options={{
              minimap: { enabled: false },
              fontSize: 14,
              lineNumbers: 'on',
              scrollBeyondLastLine: false,
              wordWrap: 'on',
              tabSize: 2,
              insertSpaces: true,
              automaticLayout: true
            }}
          />
        )}
      </div>

      <p style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '12px', marginBottom: 0 }}>
        Config path: ~/.ea/nexus/config.yaml • Changes take effect immediately after save
      </p>
    </div>
  )
}
