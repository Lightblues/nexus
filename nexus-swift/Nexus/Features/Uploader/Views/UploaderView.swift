import SwiftUI
import AppKit
import Combine

/// Full uploader UI for the MainWindow. Mirrors UploaderView.tsx:
///   - drop zone at the top
///   - selected image preview + compression options
///   - quality slider + format picker (live re-compression preview)
///   - path / filename inputs (recent-paths suggestions)
///   - upload button → CDN URL on clipboard
///   - recent uploads list at the bottom
///
/// The compression preview is debounced via Combine so dragging the slider
/// doesn't fire dozens of encodes per second.
struct UploaderView: View {
    @EnvironmentObject var service: UploaderService
    @EnvironmentObject var repository: UploaderRepository
    @EnvironmentObject var config: ConfigService

    @State private var image: WorkingImage?
    @State private var path: String = ""
    @State private var filename: String = ""
    @State private var quality: Int = 80
    @State private var outputFormat: OutputFormat = .auto
    @State private var showAdvanced: Bool = false
    @State private var uploading: Bool = false
    @State private var message: Message?

    /// Debounce subject for live recompression. Anything mutating
    /// (image bytes, quality, format) writes to this; subscriber reads it
    /// 250ms later and re-encodes once.
    @State private var recompressTrigger = PassthroughSubject<Void, Never>()
    @State private var recompressCancellable: AnyCancellable?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !service.isConfigured {
                        notConfiguredBanner
                    }

                    DropZoneView(
                        disabled: !service.isConfigured || uploading,
                        onSelect: { data, name in selectImage(data: data, name: name) },
                        onPasteClipboard: pasteClipboard
                    )

                    if let img = image {
                        previewSection(img)
                    }

                    if let msg = message {
                        messageBanner(msg)
                    }

                    Divider().padding(.vertical, 4)
                    historySection
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            installRecompressPipeline()
            adoptConfigDefaults()
            consumePendingImage()
        }
        .onChange(of: service.pendingImage?.filename) { _ in
            consumePendingImage()
        }
        .onChange(of: quality) { _ in recompressTrigger.send() }
        .onChange(of: outputFormat) { _ in recompressTrigger.send() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 16))
            Text("Image Uploader")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var notConfiguredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Set GitHub token, owner, and repo in Settings → Uploader to enable uploads.")
                .font(.system(size: 12))
            Spacer()
        }
        .padding(10)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Preview + options

    @ViewBuilder
    private func previewSection(_ img: WorkingImage) -> some View {
        // Preview thumbnail
        VStack(alignment: .leading, spacing: 8) {
            previewThumbnail(img)
            statsLine(img)
            compressionToggle(img)
            if showAdvanced {
                compressionControls
            }
            pathField
            filenameField
            uploadButton
        }
    }

    private func previewThumbnail(_ img: WorkingImage) -> some View {
        let bytes = img.compressed?.data ?? img.originalData
        return HStack(alignment: .top, spacing: 12) {
            if let nsImg = NSImage(data: bytes) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(img.meta.width) × \(img.meta.height)")
                    .font(.system(size: 12, weight: .medium))
                Text((img.compressed?.outputFormat.rawValue ?? img.meta.format.rawValue).uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func statsLine(_ img: WorkingImage) -> some View {
        HStack(spacing: 8) {
            Text("Original: \(formatBytes(img.originalData.count))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let c = img.compressed {
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Compressed: \(formatBytes(c.compressedSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                let saved = img.originalData.count - c.compressedSize
                if saved > 0 {
                    Text("(\(percentSaved(img))% smaller)")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                } else {
                    Text("(no savings)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
    }

    private func compressionToggle(_ img: WorkingImage) -> some View {
        Button(action: { showAdvanced.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                Text("Compression")
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var compressionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quality")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(quality)")
                    .font(.system(size: 11, design: .monospaced))
            }
            Slider(value: Binding(
                get: { Double(quality) },
                set: { quality = Int($0) }
            ), in: 1...100, step: 1)

            HStack {
                Text("Format")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $outputFormat) {
                    ForEach(visibleFormats, id: \.self) { f in
                        Text(f.label).tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var pathField: some View {
        HStack {
            Text("Path")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            TextField("upload", text: $path)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Menu {
                ForEach(repository.recentPaths, id: \.self) { p in
                    Button(p) { path = p }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .disabled(repository.recentPaths.isEmpty)
            .help("Recent paths")
        }
    }

    private var filenameField: some View {
        HStack {
            Text("Filename")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            TextField("name.png", text: $filename)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private var uploadButton: some View {
        HStack {
            Spacer()
            Button(action: performUpload) {
                if uploading {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Uploading…")
                    }
                } else {
                    Text("Upload")
                        .frame(minWidth: 80)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(uploading || filename.isEmpty || image == nil || !service.isConfigured)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Uploads")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(repository.history.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if repository.history.isEmpty {
                Text("No uploads yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(repository.history.prefix(20)) { rec in
                    UploadHistoryRow(
                        record: rec,
                        thumbnailURL: repository.thumbnailURL(id: rec.id),
                        onCopy: {
                            service.copyToClipboard(rec.cdnUrl)
                            flash("URL copied!", kind: .success)
                        },
                        onDelete: { Task { await repository.delete(id: rec.id) } }
                    )
                }
            }
        }
    }

    // MARK: - Logic

    private func selectImage(data: Data, name: String) {
        do {
            let meta = try service.meta(data)
            let baseName = (name as NSString).deletingPathExtension
            let ext = meta.format == .jpeg ? "jpg" : meta.format.rawValue
            self.filename = "\(baseName).\(ext)"
            self.image = WorkingImage(originalData: data, originalName: name, meta: meta, compressed: nil)
            self.message = nil
            recompressTrigger.send()
        } catch {
            flash("Could not read image: \(error.localizedDescription)", kind: .error)
        }
    }

    private func pasteClipboard() {
        guard let data = service.clipboardImage() else {
            flash("No image in clipboard.", kind: .error)
            return
        }
        let stamp = Self.timestamp()
        selectImage(data: data, name: "clipboard-\(stamp).png")
    }

    private func consumePendingImage() {
        if let p = service.takePending() {
            selectImage(data: p.data, name: p.filename)
        }
    }

    private func adoptConfigDefaults() {
        let cfg = config.config.uploader
        if path.isEmpty { path = cfg.defaultPath }
        quality = cfg.compress.quality
        if let f = OutputFormat(rawValue: cfg.compress.defaultFormat) {
            outputFormat = f
        }
    }

    /// Wire up the debounced compression pipeline.
    private func installRecompressPipeline() {
        guard recompressCancellable == nil else { return }
        recompressCancellable = recompressTrigger
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { runCompression() }
    }

    private func runCompression() {
        guard let img = image else { return }
        let data = img.originalData
        let q = quality
        let f = outputFormat
        Task.detached(priority: .userInitiated) {
            do {
                let result = try ImageCompressor.compress(data, quality: q, format: f)
                await MainActor.run {
                    guard var current = self.image, current.originalData == data else { return }
                    current.compressed = result
                    self.image = current
                    // If output format changed (auto-pick) re-derive extension
                    let ext = result.outputFormat == .jpeg ? "jpg" : result.outputFormat.rawValue
                    let baseName = (self.filename as NSString).deletingPathExtension
                    if !baseName.isEmpty {
                        self.filename = "\(baseName).\(ext)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.flash("Compression failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    private func performUpload() {
        guard let img = image, let compressed = img.compressed else {
            flash("Image not ready yet — wait for compression.", kind: .error)
            return
        }
        uploading = true
        message = nil
        let bytes = compressed.data
        let outFormat = compressed.outputFormat
        let pathValue = path
        let nameValue = filename
        let metaValue = ImageMeta(
            format: outFormat,
            width: compressed.width,
            height: compressed.height,
            hasAlpha: img.meta.hasAlpha
        )
        let originalData = img.originalData
        Task {
            do {
                _ = try await service.upload(
                    originalData: originalData,
                    compressedData: bytes,
                    meta: metaValue,
                    outputFormat: outFormat,
                    filename: nameValue,
                    path: pathValue
                )
                self.image = nil
                self.filename = ""
                self.flash("Uploaded — URL copied to clipboard.", kind: .success)
            } catch {
                self.flash("Upload failed: \(error.localizedDescription)", kind: .error)
            }
            self.uploading = false
        }
    }

    private func flash(_ text: String, kind: Message.Kind) {
        message = Message(text: text, kind: kind)
    }

    @ViewBuilder
    private func messageBanner(_ msg: Message) -> some View {
        let color: Color = msg.kind == .success ? .green : .red
        HStack {
            Image(systemName: msg.kind == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(color)
            Text(msg.text).font(.system(size: 12))
            Spacer()
            Button("Dismiss") { message = nil }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    private var visibleFormats: [OutputFormat] {
        // Hide WebP if ImageIO can't encode it on this OS — encoding will
        // fall back to PNG anyway, but the picker should reflect reality.
        ImageCompressor.webpEncodeSupported
            ? OutputFormat.allCases
            : OutputFormat.allCases.filter { $0 != .webp }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func percentSaved(_ img: WorkingImage) -> Int {
        guard let c = img.compressed, img.originalData.count > 0 else { return 0 }
        return Int(round(Double(img.originalData.count - c.compressedSize) / Double(img.originalData.count) * 100))
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

/// Bundle of "image being worked on" — original bytes + meta + latest
/// compressed result. `compressed` is nil while encoding.
private struct WorkingImage: Equatable {
    let originalData: Data
    let originalName: String
    let meta: ImageMeta
    var compressed: CompressResult?
}

private struct Message: Equatable {
    enum Kind { case success, error }
    let text: String
    let kind: Kind
}
