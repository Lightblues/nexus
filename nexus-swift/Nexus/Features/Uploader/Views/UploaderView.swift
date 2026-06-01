import SwiftUI
import AppKit
import Combine

/// Full uploader UI — batch mode (up to 10 images per drop).
///
/// Each batch item carries its own filename, compress result, and per-item
/// upload status. The compression slider/format applies to all items, but we
/// only re-encode the *active* item live; the others lazily compress on
/// demand (when you click them, or when Upload All gets to them). This keeps
/// CPU sane while you're tuning quality with 10 images selected.
///
/// Layout (top → bottom):
///   - drop zone
///   - thumbnail strip (one button per batch item, shows active + status)
///   - active item: preview + size delta
///   - compression controls (quality slider / format picker)
///   - path + filename inputs
///   - Upload All button + per-item progress footer
///   - recent history list
struct UploaderView: View {
    @EnvironmentObject var service: UploaderService
    @EnvironmentObject var repository: UploaderRepository
    @EnvironmentObject var config: ConfigService

    @State private var batch: [BatchItem] = []
    @State private var activeIndex: Int = 0
    @State private var path: String = ""
    @State private var quality: Int = 80
    @State private var outputFormat: OutputFormat = .auto
    @State private var showAdvanced: Bool = false
    @State private var uploading: Bool = false
    @State private var message: Message?

    /// Debounce subject for live recompression of the active item only.
    @State private var recompressTrigger = PassthroughSubject<Void, Never>()
    @State private var recompressCancellable: AnyCancellable?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !service.isConfigured { notConfiguredBanner }

                    DropZoneView(
                        disabled: !service.isConfigured || uploading,
                        onSelect: { drops in addToBatch(drops) },
                        onPasteClipboard: pasteClipboard
                    )

                    if !batch.isEmpty {
                        thumbnailStrip
                        if let active = activeItem {
                            previewSection(active)
                        }
                    }

                    if let msg = message { messageBanner(msg) }

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
        .onChange(of: quality) { _ in invalidateActiveCompress() }
        .onChange(of: outputFormat) { _ in invalidateActiveCompress() }
        .onChange(of: activeIndex) { _ in recompressTrigger.send() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 16))
            Text("Image Uploader")
                .font(.system(size: 16, weight: .semibold))
            if !batch.isEmpty {
                Text("(\(batch.count) image\(batch.count == 1 ? "" : "s"))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !batch.isEmpty && !uploading {
                Button(role: .destructive, action: clearBatch) {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
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

    // MARK: - Thumbnail strip

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(batch.enumerated()), id: \.element.id) { idx, item in
                    BatchThumbnail(
                        item: item,
                        isActive: idx == activeIndex,
                        onSelect: { activeIndex = idx },
                        onRemove: uploading ? nil : { removeFromBatch(at: idx) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Preview section (active item)

    @ViewBuilder
    private func previewSection(_ item: BatchItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            previewThumbnail(item)
            statsLine(item)
            compressionToggle()
            if showAdvanced { compressionControls }
            pathField
            filenameField(itemId: item.id)
            uploadAllButton
        }
    }

    private func previewThumbnail(_ item: BatchItem) -> some View {
        let bytes = item.compressed?.data ?? item.originalData
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
                Text("\(item.meta.width) × \(item.meta.height)")
                    .font(.system(size: 12, weight: .medium))
                Text((item.compressed?.outputFormat.rawValue ?? item.meta.format.rawValue).uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func statsLine(_ item: BatchItem) -> some View {
        HStack(spacing: 8) {
            Text("Original: \(formatBytes(item.originalData.count))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let c = item.compressed {
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Compressed: \(formatBytes(c.compressedSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                let saved = item.originalData.count - c.compressedSize
                if saved > 0 {
                    Text("(\(percentSaved(item))% smaller)")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                } else {
                    Text("(no savings)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("(compressing…)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func compressionToggle() -> some View {
        Button(action: { showAdvanced.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                Text("Compression (applies to all)")
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

    /// Filename input for the *active* item only. Editing here updates that
    /// item's filename in `batch`. (Other items keep their own dedup'd names.)
    private func filenameField(itemId: UUID) -> some View {
        HStack {
            Text("Filename")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            TextField("name.png", text: Binding(
                get: { batch.first(where: { $0.id == itemId })?.filename ?? "" },
                set: { newName in
                    if let idx = batch.firstIndex(where: { $0.id == itemId }) {
                        batch[idx].filename = newName
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
        }
    }

    private var uploadAllButton: some View {
        HStack {
            if uploading {
                let done = batch.filter { $0.status.isTerminal }.count
                Text("Uploading \(done)/\(batch.count)…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: uploadAll) {
                if uploading {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Uploading…")
                    }
                } else {
                    Text(batch.count <= 1 ? "Upload" : "Upload All (\(batch.count))")
                        .frame(minWidth: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(uploading || batch.isEmpty || !service.isConfigured)
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

    // MARK: - Batch state mutations

    private var activeItem: BatchItem? {
        guard batch.indices.contains(activeIndex) else { return nil }
        return batch[activeIndex]
    }

    /// Add new images to the batch, respecting the maxBatch cap and
    /// auto-deduping filenames so multi-screenshot drops don't overwrite
    /// each other on GitHub PUT.
    private func addToBatch(_ drops: [DropZoneView.DroppedImage]) {
        guard !drops.isEmpty else { return }
        let cap = DropZoneView.maxBatch
        let remaining = max(0, cap - batch.count)
        if remaining == 0 {
            flash("Already at \(cap) image limit. Upload or clear first.", kind: .error)
            return
        }
        let accepted = drops.prefix(remaining)
        if drops.count > remaining {
            flash("Added \(remaining) of \(drops.count) — batch capped at \(cap).", kind: .error)
        }

        var existingNames = Set(batch.map { $0.filename.lowercased() })
        var added: [BatchItem] = []
        for drop in accepted {
            do {
                let meta = try service.meta(drop.data)
                let baseName = (drop.filename as NSString).deletingPathExtension
                let ext = meta.format == .jpeg ? "jpg" : meta.format.rawValue
                let firstChoice = "\(baseName).\(ext)"
                let unique = uniquify(firstChoice, against: &existingNames)
                let item = BatchItem(
                    id: UUID(),
                    originalData: drop.data,
                    originalName: drop.filename,
                    filename: unique,
                    meta: meta,
                    compressed: nil,
                    status: .pending
                )
                added.append(item)
            } catch {
                Log.uploader.error("skipping \(drop.filename): \(error.localizedDescription)")
            }
        }
        let wasEmpty = batch.isEmpty
        batch.append(contentsOf: added)
        if wasEmpty { activeIndex = 0 }
        recompressTrigger.send()
    }

    private func removeFromBatch(at idx: Int) {
        guard batch.indices.contains(idx) else { return }
        batch.remove(at: idx)
        if batch.isEmpty {
            activeIndex = 0
        } else if activeIndex >= batch.count {
            activeIndex = batch.count - 1
        }
    }

    private func clearBatch() {
        batch.removeAll()
        activeIndex = 0
    }

    /// Append `-2`, `-3`, … if `name` already exists in `taken`, then mark
    /// the chosen name as taken. Case-insensitive (GitHub paths are
    /// case-sensitive but filesystems often aren't, and users get confused).
    private func uniquify(_ name: String, against taken: inout Set<String>) -> String {
        let lower = name.lowercased()
        if !taken.contains(lower) {
            taken.insert(lower)
            return name
        }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        for n in 2...999 {
            let candidate = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            if !taken.contains(candidate.lowercased()) {
                taken.insert(candidate.lowercased())
                return candidate
            }
        }
        return name   // pathological, give up
    }

    private func pasteClipboard() {
        guard let data = service.clipboardImage() else {
            flash("No image in clipboard.", kind: .error)
            return
        }
        let stamp = Self.timestamp()
        addToBatch([(data, "clipboard-\(stamp).png")])
    }

    private func consumePendingImage() {
        if let p = service.takePending() {
            addToBatch([(p.data, p.filename)])
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

    // MARK: - Compression pipeline

    private func installRecompressPipeline() {
        guard recompressCancellable == nil else { return }
        recompressCancellable = recompressTrigger
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { runCompression() }
    }

    /// Settings (quality / format) changed → invalidate every item's
    /// compressed result and re-encode the active one. Others will be
    /// re-encoded lazily when you click them or when Upload All hits them.
    private func invalidateActiveCompress() {
        for i in batch.indices { batch[i].compressed = nil }
        recompressTrigger.send()
    }

    private func runCompression() {
        guard let item = activeItem else { return }
        compressItem(itemID: item.id, quality: quality, format: outputFormat)
    }

    /// Compress one item and write the result back into `batch`. If the
    /// item's bytes have since changed (unlikely — we don't currently mutate
    /// originalData) the result is dropped.
    private func compressItem(itemID: UUID, quality q: Int, format f: OutputFormat) {
        guard let idx = batch.firstIndex(where: { $0.id == itemID }) else { return }
        let data = batch[idx].originalData
        Task.detached(priority: .userInitiated) {
            do {
                let result = try ImageCompressor.compress(data, quality: q, format: f)
                await MainActor.run {
                    guard let i = batch.firstIndex(where: { $0.id == itemID }) else { return }
                    batch[i].compressed = result
                    // If output format changed (auto-pick) reflect it in filename.
                    let ext = result.outputFormat == .jpeg ? "jpg" : result.outputFormat.rawValue
                    let baseName = (batch[i].filename as NSString).deletingPathExtension
                    let currentExt = (batch[i].filename as NSString).pathExtension.lowercased()
                    if !baseName.isEmpty, currentExt != ext {
                        batch[i].filename = "\(baseName).\(ext)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.flash("Compression failed: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    // MARK: - Upload

    private func uploadAll() {
        guard !batch.isEmpty else { return }
        uploading = true
        message = nil

        let q = quality
        let f = outputFormat
        let pathValue = path

        Task {
            var failures: [(String, String)] = []
            for itemID in batch.map(\.id) {
                // Mark uploading
                if let idx = batch.firstIndex(where: { $0.id == itemID }) {
                    batch[idx].status = .uploading
                }

                // Make sure we have a compressed result. If not, encode now
                // (this is the "lazy" path for items the user never clicked).
                if let idx = batch.firstIndex(where: { $0.id == itemID }),
                   batch[idx].compressed == nil {
                    do {
                        let data = batch[idx].originalData
                        let result = try ImageCompressor.compress(data, quality: q, format: f)
                        batch[idx].compressed = result
                        // Sync extension if auto-pick changed format.
                        let ext = result.outputFormat == .jpeg ? "jpg" : result.outputFormat.rawValue
                        let baseName = (batch[idx].filename as NSString).deletingPathExtension
                        let currentExt = (batch[idx].filename as NSString).pathExtension.lowercased()
                        if !baseName.isEmpty, currentExt != ext {
                            batch[idx].filename = "\(baseName).\(ext)"
                        }
                    } catch {
                        if let idx2 = batch.firstIndex(where: { $0.id == itemID }) {
                            batch[idx2].status = .failed(error.localizedDescription)
                        }
                        failures.append((batch[idx].filename, error.localizedDescription))
                        continue
                    }
                }

                // Snapshot the values we need outside the index.
                guard let idx = batch.firstIndex(where: { $0.id == itemID }),
                      let compressed = batch[idx].compressed
                else { continue }
                let item = batch[idx]

                let metaValue = ImageMeta(
                    format: compressed.outputFormat,
                    width: compressed.width,
                    height: compressed.height,
                    hasAlpha: item.meta.hasAlpha
                )
                do {
                    _ = try await service.upload(
                        originalData: item.originalData,
                        compressedData: compressed.data,
                        meta: metaValue,
                        outputFormat: compressed.outputFormat,
                        filename: item.filename,
                        path: pathValue
                    )
                    if let i = batch.firstIndex(where: { $0.id == itemID }) {
                        batch[i].status = .uploaded
                    }
                } catch {
                    if let i = batch.firstIndex(where: { $0.id == itemID }) {
                        batch[i].status = .failed(error.localizedDescription)
                    }
                    failures.append((item.filename, error.localizedDescription))
                }
            }

            uploading = false
            // Final summary message + auto-clear successes if nothing failed.
            let total = batch.count
            let okCount = batch.filter { $0.status == .uploaded }.count
            if failures.isEmpty {
                flash("Uploaded \(okCount) image\(okCount == 1 ? "" : "s") — last URL on clipboard.", kind: .success)
                // Clear the batch only when everything succeeded — leaves
                // failed items in place for retry.
                batch.removeAll()
                activeIndex = 0
            } else {
                let summary = "Uploaded \(okCount)/\(total). \(failures.count) failed: " +
                              failures.prefix(2).map(\.0).joined(separator: ", ") +
                              (failures.count > 2 ? "…" : "")
                flash(summary, kind: .error)
            }
        }
    }

    // MARK: - Helpers

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

    private var visibleFormats: [OutputFormat] {
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

    private func percentSaved(_ item: BatchItem) -> Int {
        guard let c = item.compressed, item.originalData.count > 0 else { return 0 }
        return Int(round(Double(item.originalData.count - c.compressedSize) / Double(item.originalData.count) * 100))
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

/// One image staged in the batch. `compressed` is filled lazily — nil until
/// either (a) user makes this the active item, or (b) Upload All gets to it.
private struct BatchItem: Identifiable, Equatable {
    let id: UUID
    let originalData: Data
    let originalName: String
    var filename: String
    let meta: ImageMeta
    var compressed: CompressResult?
    var status: BatchStatus
}

private enum BatchStatus: Equatable {
    case pending
    case uploading
    case uploaded
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .uploaded, .failed: return true
        case .pending, .uploading: return false
        }
    }
}

/// One thumbnail in the horizontal strip. Shows status badge in corner +
/// remove button on hover. Click → make active.
private struct BatchThumbnail: View {
    let item: BatchItem
    let isActive: Bool
    let onSelect: () -> Void
    /// nil → don't show remove button (e.g. mid-upload).
    let onRemove: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                ZStack(alignment: .bottomTrailing) {
                    if let nsImg = NSImage(data: item.originalData) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Rectangle().fill(.tertiary)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    statusBadge
                        .padding(4)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .help(item.filename)

            if hovering, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(2)
            }
        }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .pending:
            EmptyView()
        case .uploading:
            ProgressView()
                .controlSize(.small)
                .padding(3)
                .background(.black.opacity(0.5), in: Circle())
        case .uploaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white, .green)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.white, .red)
                .font(.system(size: 14))
        }
    }
}

private struct Message: Equatable {
    enum Kind { case success, error }
    let text: String
    let kind: Kind
}
