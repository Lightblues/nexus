import { CSSProperties, ReactNode } from 'react'

interface CardProps {
  children: ReactNode
  onClick?: () => void
  style?: CSSProperties
}

export default function Card({ children, onClick, style }: CardProps) {
  return (
    <div
      onClick={onClick}
      style={{
        background: 'var(--bg-card)',
        borderRadius: 'var(--radius)',
        padding: '16px',
        cursor: onClick ? 'pointer' : 'default',
        transition: 'transform 0.2s, box-shadow 0.2s',
        ...style
      }}
      onMouseEnter={(e) => {
        if (onClick) {
          e.currentTarget.style.transform = 'translateY(-2px)'
          e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.2)'
        }
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.transform = ''
        e.currentTarget.style.boxShadow = ''
      }}
    >
      {children}
    </div>
  )
}
