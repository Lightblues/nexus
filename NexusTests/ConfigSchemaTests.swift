import XCTest
@testable import Nexus

final class ConfigSchemaTests: XCTestCase {
    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    func testUpgradeReplacesTheOldEnrichDefaultOnly() {
        var old = AppConfig()
        old.tracker.enrichApps = ["Code", "Google Chrome"]
        XCTAssertEqual(old.upgraded().tracker.enrichApps, TrackerConfig.defaultEnrichApps)
        var custom = AppConfig()
        custom.tracker.enrichApps = ["Google Chrome"]
        XCTAssertEqual(custom.upgraded().tracker.enrichApps, ["Google Chrome"], "a list the user edited stays")
        XCTAssertTrue(TrackerConfig.defaultEnrichApps.contains("Cursor"))
    }

    func testEmptyObjectIsAllDefaults() throws {
        XCTAssertEqual(try decode("{}"), AppConfig())
    }

    func testMissingOrMistypedFieldsFallBackOneByOne() throws {
        let config = try decode("""
        {
          "pomodoro": { "workDuration": 50, "autoStartBreak": "yes" },
          "tracker": 7,
          "uploader": { "github": { "owner": "me" }, "compress": { "quality": 60 } },
          "unknownSection": { "x": 1 }
        }
        """)
        var expected = AppConfig()
        expected.pomodoro.workDuration = 50
        expected.uploader.github.owner = "me"
        expected.uploader.compress.quality = 60
        XCTAssertEqual(config, expected)
        XCTAssertEqual(config.pomodoro.autoStartBreak, true, "a mistyped field takes its default")
        XCTAssertEqual(config.uploader.github.branch, "main")
    }

    func testRoundTrip() throws {
        var config = AppConfig()
        config.pomodoro.workDuration = 31
        config.tracker.enrichApps = ["Safari"]
        config.hotkey.palette = "Control+Space"
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(AppConfig.self, from: data), config)
    }

    func testNotAnObjectStillThrows() {
        XCTAssertThrowsError(try decode("[]"))
    }
}
