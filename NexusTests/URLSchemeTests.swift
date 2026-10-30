import XCTest
@testable import Nexus

final class URLSchemeTests: XCTestCase {
    private func parse(_ string: String) throws -> URLSchemeHandler.Parsed {
        URLSchemeHandler.parse(try XCTUnwrap(URL(string: string)))
    }

    func testCommandURL() throws {
        XCTAssertEqual(try parse("nexus://command/pomodoro.toggle"), .command("pomodoro.toggle"))
        XCTAssertEqual(try parse("nexus://command/tracker.open?x=1"), .command("tracker.open"))
    }

    func testOtherScheme() throws {
        XCTAssertEqual(try parse("https://command/pomodoro.toggle"), .notNexus)
    }

    func testWrongHost() throws {
        XCTAssertEqual(try parse("nexus://palette/pomodoro.toggle"), .unsupportedHost("palette"))
    }

    func testEmptyID() throws {
        XCTAssertEqual(try parse("nexus://command"), .emptyID)
        XCTAssertEqual(try parse("nexus://command/"), .emptyID)
    }

    @MainActor
    func testUnknownIDIsNotInTheRegistry() throws {
        CommandRegistry.shared.register(Command(id: "test.known", title: "Known", run: {}))
        guard case .command(let known) = try parse("nexus://command/test.known"),
              case .command(let unknown) = try parse("nexus://command/test.unknown") else { return XCTFail("both parse as commands") }
        XCTAssertNotNil(CommandRegistry.shared.find(id: known))
        XCTAssertNil(CommandRegistry.shared.find(id: unknown))
    }
}
