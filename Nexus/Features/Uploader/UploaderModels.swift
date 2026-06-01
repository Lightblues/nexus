import Foundation

/// Output format choice for compression.
enum OutputFormat: String, Codable, CaseIterable, Identifiable {
    case auto, webp, jpeg, png
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto (Smart)"
        case .webp: return "WebP"
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        }
    }
}

/// Image format we recognize. Stored in DB.
enum ImageFormat: String, Codable {
    case png, jpeg, webp, gif
}

/// Lightweight metadata extracted from an image's bytes.
struct ImageMeta: Equatable {
    let format: ImageFormat
    let width: Int
    let height: Int
    let hasAlpha: Bool
}

/// Result of running an image through the compressor.
struct CompressResult: Equatable {
    let data: Data
    let originalSize: Int
    let compressedSize: Int
    let width: Int
    let height: Int
    let outputFormat: ImageFormat
}

/// One row of `upload_history`.
struct UploadRecord: Identifiable, Equatable {
    let id: String                 // UUID
    let filename: String
    let originalName: String
    let timestamp: Date
    let originalSize: Int
    let compressedSize: Int
    let width: Int
    let height: Int
    let format: ImageFormat
    let path: String?              // remote folder
    let cdnUrl: String
    let sha: String
    /// GitHub owner/repo/branch this upload landed in, captured at upload
    /// time. Lets us build the GitHub blob URL even after the user has
    /// re-pointed Settings at a different repo. Nil for v3-era rows.
    let githubOwner: String?
    let githubRepo: String?
    let githubBranch: String?

    /// `https://github.com/{owner}/{repo}/blob/{branch}/{path}/{filename}`,
    /// or nil if any of the github_* columns is missing.
    var githubURL: URL? {
        guard let owner = githubOwner, !owner.isEmpty,
              let repo = githubRepo, !repo.isEmpty,
              let branch = githubBranch, !branch.isEmpty
        else { return nil }
        let folder = path.flatMap { $0.isEmpty ? nil : $0 }
        let fullPath = folder.map { "\($0)/\(filename)" } ?? filename
        let encoded = fullPath
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "https://github.com/\(owner)/\(repo)/blob/\(branch)/\(encoded)")
    }
}

/// Outcome of a GitHub PUT.
struct UploadOutcome: Equatable {
    let cdnUrl: String
    let sha: String
}

/// Image temporarily held in memory after a tray-icon drop, picked up by the
/// uploader view when it next mounts.
struct PendingImage: Equatable {
    let data: Data
    let filename: String
}

enum UploaderError: LocalizedError {
    case notConfigured
    case unsupportedFormat
    case compressionFailed(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Uploader not configured. Set GitHub token, owner, and repo in Settings."
        case .unsupportedFormat:
            return "Image format not supported."
        case .compressionFailed(let why):
            return "Compression failed: \(why)"
        case .http(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}
