import XCTest
@testable import Nexus

final class TestHostTests: XCTestCase {
    /// The host app must start no services, or the suite would open the user's real database.
    func testHostStartsNoServices() {
        XCTAssertTrue(NexusMain.isHostingTests)
        XCTAssertNil(NSApplication.shared.delegate as? AppDelegate)
    }
}
