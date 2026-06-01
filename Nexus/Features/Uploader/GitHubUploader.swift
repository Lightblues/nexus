import Foundation

/// Thin actor wrapping the two GitHub Contents API calls we use:
///   GET  /repos/{owner}/{repo}/contents/{path}?ref={branch}   (to learn an
///        existing file's sha so we can update it)
///   PUT  /repos/{owner}/{repo}/contents/{path}                (create or update)
///
/// We reach for URLSession + plain JSON instead of @octokit-style SDK because
/// we only need two endpoints and don't want a transitive dep tree for a
/// process that should stay small. Same auth: `Authorization: Bearer <token>`.
actor GitHubUploader {
    private var config: GitHubConfig?

    func configure(_ cfg: GitHubConfig) {
        config = cfg.token.isEmpty ? nil : cfg
    }

    /// Returns the CDN URL + new SHA on success.
    /// On 404 from the GET (file doesn't yet exist), we PUT without a sha to
    /// create it. On any other GET error we still attempt the PUT — GitHub
    /// will reject if it actually needs a sha.
    func upload(data: Data, path: String, filename: String, cdnBaseUrl: String) async throws -> UploadOutcome {
        guard let cfg = config else { throw UploaderError.notConfigured }

        let fullPath = path.isEmpty ? filename : "\(path)/\(filename)"
        let existingSha = try? await fetchSha(cfg: cfg, path: fullPath)

        struct Body: Encodable {
            let message: String
            let content: String
            let branch: String
            let sha: String?
        }
        let body = Body(
            message: "Upload \(filename) via Nexus",
            content: data.base64EncodedString(),
            branch: cfg.branch,
            sha: existingSha
        )
        let url = contentsURL(cfg: cfg, path: fullPath)
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Nexus", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(body)

        let (respData, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        guard let http, (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: respData, encoding: .utf8) ?? "<no body>"
            Log.uploader.error("PUT \(fullPath) failed: \(http?.statusCode ?? -1) \(bodyStr)")
            throw UploaderError.http(http?.statusCode ?? -1, bodyStr)
        }

        struct Response: Decodable {
            struct Content: Decodable { let sha: String }
            let content: Content
        }
        let parsed = try JSONDecoder().decode(Response.self, from: respData)
        let cdnUrl = "\(cdnBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(cfg.owner)/\(cfg.repo)@\(cfg.branch)/\(fullPath)"
        Log.uploader.info("PUT \(fullPath) ok, cdn=\(cdnUrl)")
        return UploadOutcome(cdnUrl: cdnUrl, sha: parsed.content.sha)
    }

    /// Best-effort delete of a previously-uploaded file. Used by the history
    /// row's delete button (currently not wired in v1; included for parity).
    func delete(path: String, sha: String) async throws {
        guard let cfg = config else { throw UploaderError.notConfigured }
        struct Body: Encodable {
            let message: String
            let sha: String
            let branch: String
        }
        let body = Body(message: "Delete \(path) via Nexus", sha: sha, branch: cfg.branch)
        var req = URLRequest(url: contentsURL(cfg: cfg, path: path))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Nexus", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(body)

        let (respData, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        guard let http, (200...299).contains(http.statusCode) else {
            let bodyStr = String(data: respData, encoding: .utf8) ?? "<no body>"
            throw UploaderError.http(http?.statusCode ?? -1, bodyStr)
        }
        Log.uploader.info("DELETE \(path) ok")
    }

    // MARK: - Internals

    private func fetchSha(cfg: GitHubConfig, path: String) async throws -> String {
        var url = contentsURL(cfg: cfg, path: path)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "ref", value: cfg.branch)]
        url = comps.url!

        var req = URLRequest(url: url)
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Nexus", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        guard let http, http.statusCode == 200 else {
            // 404 → file doesn't exist yet, totally fine.
            throw UploaderError.http(http?.statusCode ?? -1, "")
        }
        struct R: Decodable { let sha: String }
        return try JSONDecoder().decode(R.self, from: data).sha
    }

    private func contentsURL(cfg: GitHubConfig, path: String) -> URL {
        // Path components in the URL must be percent-encoded individually so
        // that `/` between segments stays unencoded but spaces in filenames
        // become `%20`.
        let encodedPath = path
            .split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "https://api.github.com/repos/\(cfg.owner)/\(cfg.repo)/contents/\(encodedPath)")!
    }
}
