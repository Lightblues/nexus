import sharp from 'sharp'
import { logger } from '../../core/Logger'
import type { CompressResultMain } from './types'

type OutputFormat = 'auto' | 'webp' | 'jpeg' | 'png'

export async function compressImage(
  buffer: Buffer,
  quality: number,
  outputFormat: OutputFormat = 'auto'
): Promise<CompressResultMain & { outputFormat: string }> {
  const originalSize = buffer.length
  let image = sharp(buffer)
  const metadata = await image.metadata()
  let { width = 0, height = 0, channels = 3 } = metadata
  const inputFormat = metadata.format as 'png' | 'jpeg' | 'webp' | 'gif'
  const hasAlpha = channels === 4

  logger.info(`Input image: ${inputFormat}, ${width}x${height}, alpha=${hasAlpha}, size=${originalSize}`)

  // Strategy: Smart format selection for best compression
  let outputBuffer: Buffer
  let selectedFormat: string

  if (outputFormat === 'auto') {
    // GIF: preserve as-is (animation support needed)
    if (inputFormat === 'gif') {
      outputBuffer = await image.toBuffer()
      selectedFormat = 'gif'
      logger.info('GIF detected, preserving original format')
    }
    // Has transparency: WebP (best) or PNG fallback
    else if (hasAlpha) {
      const webpBuffer = await image.webp({ quality, effort: 6 }).toBuffer()
      // If WebP is larger than original, keep PNG
      if (webpBuffer.length < originalSize) {
        outputBuffer = webpBuffer
        selectedFormat = 'webp'
        logger.info('Transparency detected, using WebP')
      } else {
        outputBuffer = await image.png({ compressionLevel: 9, palette: true }).toBuffer()
        selectedFormat = 'png'
        logger.info('WebP larger than original, using optimized PNG')
      }
    }
    // No transparency: JPEG mozjpeg vs WebP, pick smaller
    else {
      const [jpegBuffer, webpBuffer] = await Promise.all([
        image.jpeg({ quality, mozjpeg: true }).toBuffer(),
        image.webp({ quality, effort: 6 }).toBuffer()
      ])
      if (jpegBuffer.length <= webpBuffer.length) {
        outputBuffer = jpegBuffer
        selectedFormat = 'jpeg'
        logger.info('No transparency, JPEG smaller than WebP')
      } else {
        outputBuffer = webpBuffer
        selectedFormat = 'webp'
        logger.info('No transparency, WebP smaller than JPEG')
      }
    }
  } else if (outputFormat === 'webp') {
    outputBuffer = await image.webp({ quality, effort: 6 }).toBuffer()
    selectedFormat = 'webp'
  } else if (outputFormat === 'jpeg') {
    outputBuffer = await image.jpeg({ quality, mozjpeg: true }).toBuffer()
    selectedFormat = 'jpeg'
  } else {
    outputBuffer = await image.png({ compressionLevel: 9, palette: true }).toBuffer()
    selectedFormat = 'png'
  }

  const compressedSize = outputBuffer.length
  const savings = ((originalSize - compressedSize) / originalSize * 100).toFixed(1)
  logger.info(`Compressed: ${originalSize} -> ${compressedSize} (${savings}% reduction) as ${selectedFormat}`)

  return {
    buffer: outputBuffer,
    originalSize,
    compressedSize,
    width,
    height,
    outputFormat: selectedFormat
  }
}

export async function getImageMeta(buffer: Buffer): Promise<{
  format: 'png' | 'jpeg' | 'webp' | 'gif'
  width: number
  height: number
}> {
  const metadata = await sharp(buffer).metadata()
  return {
    format: (metadata.format || 'png') as 'png' | 'jpeg' | 'webp' | 'gif',
    width: metadata.width || 0,
    height: metadata.height || 0
  }
}

export async function generateThumbnail(buffer: Buffer, size: number = 200): Promise<Buffer> {
  return sharp(buffer)
    .resize(size, size, { fit: 'inside' })
    .webp({ quality: 80 })
    .toBuffer()
}
