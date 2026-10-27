import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The two calls the engine makes against a sync server.
public protocol SyncAPI: Sendable {
    /// Identifies the server; a different value means first contact.
    var endpoint: String { get }
    func push(device: String, items: [SyncRecord]) async throws -> [PushResult]
    func pull(since cursor: Int64) async throws -> PullPage
}

public enum SyncError: Error, Equatable {
    /// Non-2xx answer, with the server's error code when it sent one.
    case http(status: Int, code: String?)
    case badResponse
}

/// HTTP client for `services/server` (`/api/sync/push`, `/api/sync/pull`).
public struct SyncClient: SyncAPI {
    public let baseURL: URL
    private let key: String
    private let session: URLSession

    public init(baseURL: URL, key: String, session: URLSession = .shared) {
        self.baseURL = baseURL; self.key = key; self.session = session
    }

    public var endpoint: String { baseURL.absoluteString }

    public func push(device: String, items: [SyncRecord]) async throws -> [PushResult] {
        struct Body: Encodable { let device: String; let items: [SyncRecord] }
        struct Answer: Decodable { let results: [PushResult] }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/sync/push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(device: device, items: items))
        let results = try await send(request, as: Answer.self).results
        guard results.count == items.count else { throw SyncError.badResponse }
        return results
    }

    public func pull(since cursor: Int64) async throws -> PullPage {
        var parts = URLComponents(url: baseURL.appendingPathComponent("api/sync/pull"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "since", value: String(cursor))]
        guard let url = parts?.url else { throw SyncError.badResponse }
        return try await send(URLRequest(url: url), as: PullPage.self)
    }

    private func send<T: Decodable>(_ request: URLRequest, as: T.Type) async throws -> T {
        var request = request
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { done in
            session.dataTask(with: request) { data, response, error in
                if let error { done.resume(throwing: error) }
                else if let data, let response { done.resume(returning: (data, response)) }
                else { done.resume(throwing: SyncError.badResponse) }
            }.resume()
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw SyncError.badResponse }
        guard (200..<300).contains(status) else {
            throw SyncError.http(status: status, code: (try? JSONDecoder().decode(Failure.self, from: data))?.error.code)
        }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw SyncError.badResponse }
    }

    private struct Failure: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
}
