import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Smart compression mirroring the Electron sharp-based logic:
///   - GIF: keep as-is (preserve animation; ImageIO can't recompose).
///   - alpha channel present: try WebP, fall back to PNG if WebP is bigger.
///   - no alpha: try JPEG mozjpeg-equivalent + WebP, pick the smaller.
///   - explicit format: encode that.
///
/// macOS 13+ ships ImageIO WebP encode/decode, but availability across point
/// releases has been spotty. We probe at startup; if WebP encoding fails we
/// hide the WebP option in the UI and fall back to JPEG/PNG paths.
enum ImageCompressor {

    // MARK: - Probe (called once at app start)

    /// True if ImageIO can encode WebP on this OS. Result is cached.
    static let webpEncodeSupported: Bool = {
        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return supported.contains(UTType.webP.identifier)
    }()

    // MARK: - Public API

    /// Lightweight peek at format + dimensions + alpha. No decode of pixels.
    static func meta(_ data: Data) throws -> ImageMeta {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw UploaderError.unsupportedFormat
        }
        let format = detectFormat(src)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let width  = (props[kCGImagePropertyPixelWidth]  as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let hasAlpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false
        return ImageMeta(format: format, width: width, height: height, hasAlpha: hasAlpha)
    }

    /// Run the chosen strategy. `quality` ∈ 1...100 (mapped to 0...1 for
    /// lossy encoders).
    static func compress(_ data: Data, quality: Int, format: OutputFormat) throws -> CompressResult {
        let meta = try meta(data)
        let q = max(0.01, min(1.0, Double(quality) / 100.0))
        let originalSize = data.count

        Log.uploader.info("input \(meta.format.rawValue) \(meta.width)x\(meta.height) alpha=\(meta.hasAlpha) size=\(originalSize)")

        switch format {
        case .auto:
            return try autoStrategy(data: data, meta: meta, quality: q, originalSize: originalSize)
        case .webp:
            guard webpEncodeSupported else {
                // Caller forced WebP but OS can't — fall back to PNG so the
                // user gets *something* rather than an error popup.
                Log.uploader.warn("WebP encode unsupported; falling back to PNG")
                return try encodePNG(data: data, meta: meta, originalSize: originalSize)
            }
            return try encodeWebP(data: data, meta: meta, quality: q, originalSize: originalSize)
        case .jpeg:
            return try encodeJPEG(data: data, meta: meta, quality: q, originalSize: originalSize)
        case .png:
            return try encodePNG(data: data, meta: meta, originalSize: originalSize)
        }
    }

    /// Generate a square-ish thumbnail, ≤`size` px on the longest edge.
    /// Used for the upload history preview cache.
    static func thumbnail(_ data: Data, size: Int = 200) throws -> Data {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw UploaderError.unsupportedFormat
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw UploaderError.compressionFailed("thumbnail generation")
        }
        // Prefer WebP for thumbs (best compression at this size). Fall back
        // to JPEG so we always have *some* cached preview.
        let preferred: UTType = webpEncodeSupported ? .webP : .jpeg
        return try encodeCG(cg, type: preferred, quality: 0.8)
    }

    // MARK: - Strategies

    enum AutoPick: Equatable { case original, webp, png, jpeg }

    /// What `.auto` keeps, from the sizes of the encodings tried. `webpSize` is nil when
    /// WebP is unsupported or failed. GIF keeps the original; alpha keeps WebP only when
    /// smaller than the original, else PNG; no alpha keeps the smaller of JPEG and WebP.
    static func autoPick(isGIF: Bool, hasAlpha: Bool, originalSize: Int, webpSize: Int?, jpegSize: Int) -> AutoPick {
        if isGIF { return .original }
        if hasAlpha { return webpSize.map { $0 < originalSize } == true ? .webp : .png }
        guard let webpSize else { return .jpeg }
        return jpegSize <= webpSize ? .jpeg : .webp
    }

    private static func autoStrategy(data: Data, meta: ImageMeta, quality: Double, originalSize: Int) throws -> CompressResult {
        if meta.format == .gif {
            Log.uploader.info("GIF detected, preserving original")
            return CompressResult(data: data, originalSize: originalSize, compressedSize: data.count,
                                  width: meta.width, height: meta.height, outputFormat: .gif)
        }
        let webp = webpEncodeSupported ? try? encodeWebP(data: data, meta: meta, quality: quality, originalSize: originalSize) : nil
        let jpeg = meta.hasAlpha ? nil : try encodeJPEG(data: data, meta: meta, quality: quality, originalSize: originalSize)
        let pick = autoPick(isGIF: false, hasAlpha: meta.hasAlpha, originalSize: originalSize,
                            webpSize: webp?.compressedSize, jpegSize: jpeg?.compressedSize ?? 0)
        Log.uploader.info("auto: alpha=\(meta.hasAlpha) original=\(originalSize) webp=\(webp.map { String($0.compressedSize) } ?? "none") jpeg=\(jpeg.map { String($0.compressedSize) } ?? "-") → \(pick)")
        switch pick {
        case .webp: return webp!
        case .jpeg: return jpeg!
        case .png, .original: return try encodePNG(data: data, meta: meta, originalSize: originalSize)
        }
    }

    // MARK: - Single-format encoders

    private static func encodeJPEG(data: Data, meta: ImageMeta, quality: Double, originalSize: Int) throws -> CompressResult {
        let cg = try decode(data)
        let out = try encodeCG(cg, type: .jpeg, quality: quality)
        return CompressResult(data: out, originalSize: originalSize, compressedSize: out.count,
                              width: meta.width, height: meta.height, outputFormat: .jpeg)
    }

    private static func encodeWebP(data: Data, meta: ImageMeta, quality: Double, originalSize: Int) throws -> CompressResult {
        let cg = try decode(data)
        let out = try encodeCG(cg, type: .webP, quality: quality)
        return CompressResult(data: out, originalSize: originalSize, compressedSize: out.count,
                              width: meta.width, height: meta.height, outputFormat: .webp)
    }

    private static func encodePNG(data: Data, meta: ImageMeta, originalSize: Int) throws -> CompressResult {
        let cg = try decode(data)
        // PNG is lossless; the quality knob is ignored. ImageIO doesn't
        // expose libimagequant-style palette quantization (that's a Sharp
        // bonus we can't trivially match). Output may be larger than a
        // pngquant-optimized version; acceptable trade-off for v1.
        let out = try encodeCG(cg, type: .png, quality: 1.0)
        return CompressResult(data: out, originalSize: originalSize, compressedSize: out.count,
                              width: meta.width, height: meta.height, outputFormat: .png)
    }

    // MARK: - Helpers

    private static func decode(_ data: Data) throws -> CGImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw UploaderError.unsupportedFormat }
        return cg
    }

    private static func encodeCG(_ cg: CGImage, type: UTType, quality: Double) throws -> Data {
        let outData = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(outData as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw UploaderError.compressionFailed("destination create \(type.identifier)")
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dst, cg, opts as CFDictionary)
        guard CGImageDestinationFinalize(dst) else {
            throw UploaderError.compressionFailed("finalize \(type.identifier)")
        }
        return outData as Data
    }

    private static func detectFormat(_ src: CGImageSource) -> ImageFormat {
        let utiRaw = (CGImageSourceGetType(src) as String?) ?? ""
        let uti = UTType(utiRaw)
        if uti == .png { return .png }
        if uti == .jpeg { return .jpeg }
        if uti == .webP { return .webp }
        if uti == .gif  { return .gif }
        // Fallback heuristic — most "auto-detected" images we'll see are PNG.
        return .png
    }
}
