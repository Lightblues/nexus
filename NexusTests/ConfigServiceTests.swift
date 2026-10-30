import XCTest
@testable import Nexus

@MainActor
final class ConfigServiceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var legacy: URL { dir.appendingPathComponent("config.json") }

    func testFreshDatabaseIsAllDefaultsAndWritesNothing() throws {
        let db = try Database.inMemory()
        let service = ConfigService(database: db, legacyFile: legacy)
        service.bootstrap()
        XCTAssertEqual(service.config, AppConfig())
        XCTAssertEqual(try db.queue.read { try ConfigService.readLeaves($0) }.count, 0)
    }

    func testLegacyFileIsImportedOnceAndRenamed() throws {
        try Data(#"{"pomodoro":{"workDuration":42},"tracker":{"enrichApps":["Code","Google Chrome"]}}"#.utf8).write(to: legacy)
        let db = try Database.inMemory()
        let service = ConfigService(database: db, legacyFile: legacy)
        service.bootstrap()
        XCTAssertEqual(service.config.pomodoro.workDuration, 42)
        XCTAssertEqual(service.config.tracker.enrichApps, TrackerConfig.defaultEnrichApps, "the old default is upgraded on import")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json.imported").path))

        let leaves = try db.queue.read { try ConfigService.readLeaves($0) }
        XCTAssertEqual(leaves["pomodoro.workDuration"], .number(42))
        XCTAssertEqual(leaves["tracker.enrichApps"], .array(TrackerConfig.defaultEnrichApps.map { .string($0) }))
    }

    func testSaveWritesOnlyChangedLeavesAndReloads() throws {
        let db = try Database.inMemory()
        let service = ConfigService(database: db, legacyFile: legacy)
        service.bootstrap()
        var edited = service.config
        edited.pomodoro.workDuration = 31
        service.save(edited)
        XCTAssertEqual(try db.queue.read { try ConfigService.readLeaves($0) }, try ConfigService.leaves(of: edited))

        try db.queue.write { try $0.execute(sql: "UPDATE settings SET value = '50' WHERE key = 'pomodoro.workDuration'") }
        let reopened = ConfigService(database: db, legacyFile: legacy)
        reopened.bootstrap()
        XCTAssertEqual(reopened.config.pomodoro.workDuration, 50)
        XCTAssertEqual(reopened.config.ui, AppConfig().ui)
    }

    func testAMistypedLeafFallsBackToItsDefault() throws {
        let db = try Database.inMemory()
        try db.queue.write { try $0.execute(sql: #"INSERT INTO settings (key, value) VALUES ('pomodoro.workDuration', '"long"'), ('ui.windowWidth', '400')"#) }
        let service = ConfigService(database: db, legacyFile: legacy)
        service.bootstrap()
        XCTAssertEqual(service.config.pomodoro.workDuration, 25)
        XCTAssertEqual(service.config.ui.windowWidth, 400)
    }
}
