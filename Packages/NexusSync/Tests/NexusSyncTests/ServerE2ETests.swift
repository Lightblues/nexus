import Foundation
import XCTest
@testable import NexusSync

/// Runs against a live `services/server` (`scripts/e2e.sh` starts one on a throwaway Postgres); skipped otherwise.
final class ServerE2ETests: XCTestCase {
    private func server() throws -> (URL, String) {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["NEXUS_E2E_URL"].flatMap(URL.init(string:)), let key = env["NEXUS_E2E_KEY"], !key.isEmpty else {
            throw XCTSkip("NEXUS_E2E_URL and NEXUS_E2E_KEY not set")
        }
        return (url, key)
    }

    func testTwoDatabasesConvergeThroughTheRealServer() async throws {
        let (url, key) = try server()
        try await converge(api: { SyncClient(baseURL: url, key: key) })

        let client = SyncClient(baseURL: url, key: key)
        var cursor: Int64 = 0
        var records: [SyncRecord] = []
        while true {
            let page = try await client.pull(since: cursor)
            records += page.records
            cursor = page.cursor
            if !page.more { break }
        }
        XCTAssertEqual(records.filter { $0.kind == "pomodoro_session" && $0.deleted }.map(\.id), ["B1"])
        XCTAssertEqual(records.filter { $0.kind == "tracker_record" }.count, 3)
        XCTAssertTrue(records.contains { $0.kind == "setting" && $0.id == "hotkey.palette" })
    }

    func testWrongKeyIsRefused() async throws {
        let (url, _) = try server()
        do {
            _ = try await SyncClient(baseURL: url, key: "wrong").pull(since: 0)
            XCTFail("expected 401")
        } catch let error as SyncError {
            XCTAssertEqual(error, .http(status: 401, code: "unauthorized"))
        }
    }
}
