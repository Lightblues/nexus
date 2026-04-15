export interface UploadRecord {
  id: string
  filename: string
  originalName: string
  timestamp: string // ISO 8601
  originalSize: number // bytes
  compressedSize: number // bytes
  width: number
  height: number
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  path: string // GitHub path (e.g., "wiki/my-article")
  cdnUrl: string
  sha: string // GitHub blob SHA
}

export interface UploaderData {
  version: 1
  recentPaths: string[]
  history: UploadRecord[]
}

export interface ImageMeta {
  buffer: Buffer
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  width: number
  height: number
  size: number
}

export interface CompressResult {
  buffer: Buffer
  originalSize: number
  compressedSize: number
  width: number
  height: number
  outputFormat?: string
}

export interface UploadResult {
  success: boolean
  cdnUrl?: string
  sha?: string
  error?: string
}

export interface UploaderConfig {
  enabled: boolean
  github: {
    token: string
    owner: string
    repo: string
    branch: string
  }
  cdn: {
    baseUrl: string
  }
  compress: {
    quality: number
    defaultFormat: 'auto' | 'webp' | 'jpeg' | 'png'
  }
  defaultPath: string
  cacheThumbnails: boolean
}
