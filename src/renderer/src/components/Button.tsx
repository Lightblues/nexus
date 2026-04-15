import { CSSProperties, ReactNode } from 'react'

interface ButtonProps {
  children: ReactNode
  onClick?: () => void
  variant?: 'primary' | 'secondary' | 'danger' | 'ghost'
  size?: 'sm' | 'md' | 'lg'
  disabled?: boolean
  style?: CSSProperties
}

const variants: Record<string, CSSProperties> = {
  primary: {
    background: 'var(--accent)',
    color: 'white'
  },
  secondary: {
    background: 'var(--bg-card)',
    color: 'var(--text-primary)'
  },
  danger: {
    background: '#dc2626',
    color: 'white'
  },
  ghost: {
    background: 'transparent',
    color: 'var(--text-secondary)'
  }
}

const sizes: Record<string, CSSProperties> = {
  sm: { padding: '6px 12px', fontSize: '12px' },
  md: { padding: '10px 20px', fontSize: '14px' },
  lg: { padding: '14px 28px', fontSize: '16px' }
}

export default function Button({
  children,
  onClick,
  variant = 'primary',
  size = 'md',
  disabled = false,
  style
}: ButtonProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      style={{
        borderRadius: 'var(--radius)',
        fontWeight: 500,
        opacity: disabled ? 0.5 : 1,
        cursor: disabled ? 'not-allowed' : 'pointer',
        ...variants[variant],
        ...sizes[size],
        ...style
      }}
    >
      {children}
    </button>
  )
}
