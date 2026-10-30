import XCTest
@testable import Nexus

final class UploaderErrorTests: XCTestCase {
    private func describe(_ error: UploaderError) -> String { String(describing: error) }

    func testGitHubStatusesMapToTypedCases() {
        XCTAssertEqual(describe(UploaderError(status: 401, body: "Bad credentials")), describe(.invalidToken))
        XCTAssertEqual(describe(UploaderError(status: 404, body: "Not Found")), describe(.repoNotFound))
        XCTAssertEqual(describe(UploaderError(status: 409, body: "sha mismatch")), describe(.fileExistsConflict))
    }

    func testOtherStatusesKeepCodeAndBody() {
        guard case .http(let code, let body) = UploaderError(status: 422, body: "Invalid request") else { return XCTFail("422 is .http") }
        XCTAssertEqual(code, 422)
        XCTAssertEqual(body, "Invalid request")
        XCTAssertEqual(UploaderError(status: 422, body: "Invalid request").errorDescription, "HTTP 422: Invalid request")
    }

    func testTypedCasesNameTheFixNotThePayload() {
        XCTAssertFalse(UploaderError(status: 401, body: "{\"message\":\"Bad credentials\"}").errorDescription!.contains("Bad credentials"))
        XCTAssertTrue(UploaderError.invalidToken.errorDescription!.contains("Settings"))
    }
}
