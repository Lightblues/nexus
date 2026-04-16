export type {
  UploadRecord,
  UploaderData,
  UploaderConfig,
  UploadResult
} from '@shared/types'

// Main-process-only types (use Node Buffer instead of number[])
export interface ImageMetaMain {
  buffer: Buffer
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  width: number
  height: number
  size: number
}

export interface CompressResultMain {
  buffer: Buffer
  originalSize: number
  compressedSize: number
  width: number
  height: number
  outputFormat?: string
}
