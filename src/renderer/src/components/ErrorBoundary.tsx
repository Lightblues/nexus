import { Component, ReactNode } from 'react'
import Button from './Button'

interface ErrorBoundaryProps {
  children: ReactNode
  fallbackLabel?: string
}

interface ErrorBoundaryState {
  hasError: boolean
  error: Error | null
}

export default class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: React.ErrorInfo): void {
    console.error(`[ErrorBoundary${this.props.fallbackLabel ? ` - ${this.props.fallbackLabel}` : ''}]`, error, info.componentStack)
  }

  handleRetry = (): void => {
    this.setState({ hasError: false, error: null })
  }

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        <div style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          height: '100%',
          padding: '24px',
          textAlign: 'center',
          gap: '12px'
        }}>
          <div style={{ fontSize: '32px' }}>⚠️</div>
          <div style={{ fontSize: '14px', fontWeight: 500 }}>
            {this.props.fallbackLabel || 'Something'} failed to load
          </div>
          <div style={{
            fontSize: '12px',
            color: 'var(--text-secondary)',
            maxWidth: '260px',
            wordBreak: 'break-word'
          }}>
            {this.state.error?.message || 'An unexpected error occurred'}
          </div>
          <Button variant="secondary" size="sm" onClick={this.handleRetry}>
            Retry
          </Button>
        </div>
      )
    }
    return this.props.children
  }
}
