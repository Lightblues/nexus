import Foundation
import AppKit
import Combine

/// Coordinates the uploader's pieces: live config → GitHubUploader,
/// compression on demand, clipboard helpers, and a one-shot "pending image"
/// slot the AppDelegate uses when the user drags onto the menu bar icon.
@MainActor
final class UploaderService: ObservableObject {
    /// Read-only signal: nil means "no GitHub credentials configured".
    @Published private(set) var isConfigured: Bool = false
    /// Set by the menu bar drag receiver; consumed by the next mount of
    /// UploaderPopoverView. Reset to nil after consumption.
    @Published var pendingImage: PendingImage?

    let repository: UploaderRepository
    private let config: ConfigService
    private let github = GitHubUploader()

    private var configCancellable: AnyCancellable?

    init(repository: UploaderRepository, config: ConfigService) {
        self.repository = repository
        self.config = config
    }

    func bootstrap() async {
        await repository.bootstrap()
        configCancellable = config.$config
            .map(\.uploader)
            .removeDuplicates()
            .sink { [weak self] cfg in
                Task { @MainActor in await self?.applyConfig(cfg) }
            }
        await applyConfig(config.config.uploader)
    }

    func shutdown() async {
        // Nothing async to drain — DB writes are commit-durable; thumbnails
        // are written outside transactions but each is a single file op.
    }

    // MARK: - Public

    nonisolated func compress(_ data: Data, quality: Int, format: OutputFormat) throws -> CompressResult {
        try ImageCompressor.compress(data, quality: quality, format: format)
    }

    nonisolated func meta(_ data: Data) throws -> ImageMeta {
        try ImageCompressor.meta(data)
    }

    /// Compress (using the active config) + PUT to GitHub + record to DB +
    /// copy CDN URL to clipboard. Returns the persisted record on success.
    func upload(originalData: Data,
                compressedData: Data,
                meta: ImageMeta,
                outputFormat: ImageFormat,
                filename: String,
                path: String) async throws -> UploadRecord {
        let cfg = config.config.uploader
        guard !cfg.github.token.isEmpty,
              !cfg.github.owner.isEmpty,
              !cfg.github.repo.isEmpty
        else { throw UploaderError.notConfigured }

        let outcome = try await github.upload(
            data: compressedData,
            path: path,
            filename: filename,
            cdnBaseUrl: cfg.cdn.baseUrl
        )

        let record = UploadRecord(
            id: UUID().uuidString,
            filename: filename,
            originalName: filename,
            timestamp: Date(),
            originalSize: originalData.count,
            compressedSize: compressedData.count,
            width: meta.width,
            height: meta.height,
            format: outputFormat,
            path: path.isEmpty ? nil : path,
            cdnUrl: outcome.cdnUrl,
            sha: outcome.sha,
            githubOwner: cfg.github.owner,
            githubRepo: cfg.github.repo,
            githubBranch: cfg.github.branch
        )
        // Cache thumbnail when configured. Use the *compressed* bytes — we
        // already paid to encode them, and the thumbnail of a near-final
        // image is closer to what users see in the URL.
        var thumbnail: Data?
        if cfg.cacheThumbnails {
            thumbnail = try? ImageCompressor.thumbnail(compressedData,
                                                       size: UploaderRepository.thumbnailSize)
        }
        await repository.add(record, thumbnailData: thumbnail)
        copyToClipboard(outcome.cdnUrl)
        return record
    }

    // MARK: - Clipboard

    /// PNG bytes from the system pasteboard if the topmost item is an image.
    func clipboardImage() -> Data? {
        let pb = NSPasteboard.general
        if let png = pb.data(forType: .png) { return png }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }

    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Pending image hand-off (used by status bar drag receiver)

    func setPending(_ pending: PendingImage) {
        pendingImage = pending
    }

    /// Consume the pending image (read-once); used by UploaderPopoverView on appear.
    func takePending() -> PendingImage? {
        let p = pendingImage
        pendingImage = nil
        return p
    }

    // MARK: - Private

    private func applyConfig(_ cfg: UploaderConfig) async {
        await github.configure(cfg.github)
        let configured = !cfg.github.token.isEmpty
            && !cfg.github.owner.isEmpty
            && !cfg.github.repo.isEmpty
        if configured != isConfigured {
            isConfigured = configured
            Log.uploader.info(configured ? "configured for \(cfg.github.owner)/\(cfg.github.repo)@\(cfg.github.branch)" : "not configured")
        }
    }
}
