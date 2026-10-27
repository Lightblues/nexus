import GRDB
import XCTest
@testable import NexusSync

final class EngineTests: XCTestCase {
    private let far: Int64 = 4_000_000_000_000

    func testPushSendsRecordsAndTombstonesAndClearsTheOutbox() async throws {
        let server = FakeServer()
        let queue = try Fixture.database()
        try await queue.write { db in
            try Fixture.insertSession(db, id: "S1", tags: ["deep", "a"])
            try Fixture.insertSession(db, id: "S2")
            try Fixture.insertTracker(db)
        }
        let engine = SyncEngine(db: queue, api: server, settings: nil)
        let first = try await engine.sync()
        XCTAssertEqual(first.pushed, 3)
        XCTAssertEqual(try Fixture.outbox(queue), [])
        let s1 = await server.record("pomodoro_session", "S1")
        XCTAssertEqual(s1?.body?["tags"], .array([.string("a"), .string("deep")]))
        XCTAssertEqual(s1?.body?["completedFully"], .bool(true))
        let device = try await engine.deviceID()
        XCTAssertEqual(s1?.device, device)

        try await queue.write { db in try db.execute(sql: "DELETE FROM pomodoro_sessions WHERE id = 'S2'") }
        let second = try await engine.sync()
        XCTAssertEqual(second.pushed, 1)
        let s2 = await server.record("pomodoro_session", "S2")
        XCTAssertEqual(s2?.deleted, true)
        XCTAssertNil(s2?.body)
    }

    func testPullAppliesWithoutEchoAndHonoursTombstones() async throws {
        let server = FakeServer(pageSize: 2)
        for i in 0..<7 {
            await server.seed(SyncRecord(kind: "pomodoro_tag", id: "tag\(i)", updatedAt: 1000, body: .object(["createdAt": .number(Double(i))])))
        }
        await server.seed(SyncRecord(kind: "pomodoro_tag", id: "tag3", updatedAt: 2000, deleted: true))
        let queue = try Fixture.database()
        let engine = SyncEngine(db: queue, api: server, settings: nil)
        let report = try await engine.sync()
        XCTAssertEqual(report.pushed, 0)
        let names = try await queue.read { db in try String.fetchAll(db, sql: "SELECT name FROM pomodoro_tag_catalog ORDER BY name") }
        XCTAssertEqual(names, ["tag0", "tag1", "tag2", "tag4", "tag5", "tag6"])
        XCTAssertEqual(try Fixture.outbox(queue), [])
        let cursor = try await queue.read { db in try State.get(db, "cursor") }
        XCTAssertEqual(cursor, "8")
        let pulls = await server.pulls
        XCTAssertEqual(pulls, 4 + 1, "four pages on first contact, one empty page after the push")

        await server.seed(SyncRecord(kind: "pomodoro_tag", id: "tag0", updatedAt: 3000, deleted: true))
        _ = try await engine.sync()
        let left = try await queue.read { db in try String.fetchAll(db, sql: "SELECT name FROM pomodoro_tag_catalog ORDER BY name") }
        XCTAssertEqual(left, ["tag1", "tag2", "tag4", "tag5", "tag6"])
    }

    func testStaleAnswerIsAppliedLocally() async throws {
        let server = FakeServer()
        let queue = try Fixture.database()
        let engine = SyncEngine(db: queue, api: server, settings: nil)
        _ = try await engine.sync()

        await server.seed(SyncRecord(kind: "pomodoro_project", id: "nexus", updatedAt: far, body: .object([
            "color": .string("#111111"), "createdAt": .number(1),
        ])))
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO pomodoro_projects (name, color, created_at) VALUES ('nexus', '#ffffff', 2)")
        }
        let report = try await engine.sync()
        XCTAssertEqual(report.stale, 1)
        XCTAssertEqual(report.pushed, 0)
        let color = try await queue.read { db in try String.fetchOne(db, sql: "SELECT color FROM pomodoro_projects WHERE name = 'nexus'") }
        XCTAssertEqual(color, "#111111")
        XCTAssertEqual(try Fixture.outbox(queue), [])
        let stored = await server.record("pomodoro_project", "nexus")
        XCTAssertEqual(stored?.updatedAt, far)
    }

    func testPullDoesNotOverwriteANewerUnsentEdit() async throws {
        let server = FakeServer()
        let queue = try Fixture.database()
        try await queue.write { db in try Fixture.insertSession(db, id: "S1", project: "mine") }
        await server.seed(SyncRecord(kind: "pomodoro_session", id: "S1", updatedAt: 1, body: .object([
            "kind": .string("work"), "startTime": .number(1), "endTime": .number(2), "duration": .number(1),
            "project": .string("old"), "task": .null, "completedFully": .bool(true), "tags": .array([]),
        ])))
        let engine = SyncEngine(db: queue, api: server, settings: nil)
        _ = try await engine.sync()
        let project = try await queue.read { db in try String.fetchOne(db, sql: "SELECT project FROM pomodoro_sessions WHERE id = 'S1'") }
        XCTAssertEqual(project, "mine")
        let stored = await server.record("pomodoro_session", "S1")
        XCTAssertEqual(stored?.body?["project"], .string("mine"))
    }

    func testErrorsLeaveTheOutboxIntact() async throws {
        let server = FakeServer()
        let queue = try Fixture.database()
        try await queue.write { db in
            try Fixture.insertSession(db, id: "S1")
            try Fixture.insertSession(db, id: "S2")
        }
        let engine = SyncEngine(db: queue, api: server, settings: nil)
        await server.setFailing(true)
        do { _ = try await engine.sync(); XCTFail("expected the sync to throw") } catch {}
        XCTAssertEqual(try Fixture.outbox(queue), ["pomodoro_session S1", "pomodoro_session S2"])

        await server.setFailing(false)
        await server.setItemError("S2", "invalid_body")
        let report = try await engine.sync()
        XCTAssertEqual(report.pushed, 1)
        XCTAssertEqual(report.failed, ["pomodoro_session S2: invalid_body"])
        XCTAssertEqual(try Fixture.outbox(queue), ["pomodoro_session S2"])

        await server.setItemError("S2", nil)
        let retry = try await engine.sync()
        XCTAssertEqual(retry.pushed, 1)
        XCTAssertEqual(try Fixture.outbox(queue), [])
    }

    func testPushBatchesAtFiveHundredItems() async throws {
        let server = FakeServer()
        let queue = try Fixture.database()
        try await queue.write { db in
            for i in 0..<1203 { try db.execute(sql: "INSERT INTO pomodoro_tag_catalog (name, created_at) VALUES (?, 1)", arguments: ["t\(i)"]) }
        }
        let engine = SyncEngine(db: queue, api: server, settings: nil)
        let report = try await engine.sync()
        XCTAssertEqual(report.pushed, 1203)
        let batches = await server.pushBatches
        XCTAssertEqual(batches, [500, 500, 203])
    }

    func testPushBatchesStayUnderTheByteLimit() throws {
        let big = String(repeating: "x", count: 60 * 1024)
        let items = (0..<10).map { SyncRecord(kind: "setting", id: "k\($0)", updatedAt: 1, body: .object(["value": .string(big)])) }
        let batch = try SyncEngine.batch(items)
        XCTAssertEqual(batch.count, 4)
        XCTAssertLessThanOrEqual(try batch.map { try JSONEncoder().encode($0).count }.reduce(0, +), SyncEngine.maxBatchBytes)
    }

    // MARK: - Settings

    func testSettingsFirstContactServerWinsThenPushesMissingKeys() async throws {
        let server = FakeServer()
        await server.seed(SyncRecord(kind: "setting", id: "pomodoro.workDuration", updatedAt: 1, body: .object(["value": .number(30)])))
        await server.seed(SyncRecord(kind: "setting", id: "uploader.github.token", updatedAt: 1, body: .object(["value": .string("shared")])))
        let settings = MemorySettings()
        let engine = SyncEngine(db: try Fixture.database(), api: server, settings: settings)
        let report = try await engine.sync()

        XCTAssertEqual(settings.leaves["pomodoro.workDuration"], .number(30), "the server's value wins on first contact")
        XCTAssertEqual(settings.leaves["uploader.github.token"], .string("shared"))
        XCTAssertEqual(report.pushed, 3, "keys the server lacked are pushed")
        let stored = await server.record("setting", "pomodoro.workDuration")
        XCTAssertEqual(stored?.updatedAt, 1)
        let apps = await server.record("setting", "tracker.enrichApps")
        XCTAssertEqual(apps?.body?["value"], .array([.string("Code"), .string("Google Chrome")]))
    }

    func testSettingsLaterEditsPushAndRemoteEditsApply() async throws {
        let server = FakeServer()
        let settings = MemorySettings()
        let engine = SyncEngine(db: try Fixture.database(), api: server, settings: settings)
        _ = try await engine.sync()
        let quiet = try await engine.sync()
        XCTAssertEqual(quiet, SyncReport(), "nothing to do when nothing changed")

        settings.set("pomodoro.workDuration", .number(45))
        let edit = try await engine.sync()
        XCTAssertEqual(edit.pushed, 1)
        let stored = await server.record("setting", "pomodoro.workDuration")
        XCTAssertEqual(stored?.body?["value"], .number(45))

        await server.seed(SyncRecord(kind: "setting", id: "pomodoro.autoStartBreak", updatedAt: far, body: .object(["value": .bool(false)])))
        let pulled = try await engine.sync()
        XCTAssertEqual(pulled.pulled, 1)
        XCTAssertEqual(pulled.pushed, 0)
        XCTAssertEqual(settings.leaves["pomodoro.autoStartBreak"], .bool(false))
        XCTAssertEqual(settings.leaves["pomodoro.workDuration"], .number(45))

        await server.seed(SyncRecord(kind: "setting", id: "pomodoro.workDuration", updatedAt: far + 1, body: .object(["value": .number(50)])))
        settings.set("pomodoro.workDuration", .number(20))
        let race = try await engine.sync()
        XCTAssertEqual(race.stale, 1, "the older local edit loses to the server's")
        XCTAssertEqual(settings.leaves["pomodoro.workDuration"], .number(50))
    }

    func testDifferentServerIsFirstContactAgain() async throws {
        let queue = try Fixture.database()
        try await queue.write { db in try Fixture.insertSession(db, id: "S1") }
        let settings = MemorySettings()
        _ = try await SyncEngine(db: queue, api: FakeServer(endpoint: "fake://a"), settings: settings).sync()

        let b = FakeServer(endpoint: "fake://b")
        await b.seed(SyncRecord(kind: "setting", id: "pomodoro.workDuration", updatedAt: 1, body: .object(["value": .number(10)])))
        let report = try await SyncEngine(db: queue, api: b, settings: settings).sync()
        XCTAssertEqual(settings.leaves["pomodoro.workDuration"], .number(10))
        let pushed = await b.record("pomodoro_session", "S1")
        XCTAssertNotNil(pushed, "local records the new server lacks are pushed")
        XCTAssertEqual(report.pushed, 1 + 4, "the session and the four keys the new server lacks")
    }

    // MARK: - Two Macs

    func testTwoEnginesConverge() async throws {
        let server = FakeServer(pageSize: 3)
        try await converge(api: { server })
    }
}

/// Two Macs with different data and settings sync through one server until they hold the same rows and settings.
func converge(api: () -> any SyncAPI) async throws {
    let dbA = try Fixture.database()
    let dbB = try Fixture.database()
    try await dbA.write { db in
        try Fixture.insertSession(db, id: "A1", tags: ["deep"])
        try db.execute(sql: "INSERT INTO pomodoro_projects (name, color, created_at) VALUES ('nexus', '#3B82F6', 1)")
        try db.execute(sql: "INSERT INTO pomodoro_tag_catalog (name, created_at) VALUES ('deep', 1)")
        try Fixture.insertTracker(db, start: 100, app: "Code")
    }
    try await dbB.write { db in
        try Fixture.insertSession(db, id: "B1", project: nil)
        try db.execute(sql: "INSERT INTO pomodoro_projects (name, color, created_at) VALUES ('home', '#10B981', 2)")
        try Fixture.insertTracker(db, start: 100, app: "Code")
        try Fixture.insertTracker(db, start: 200, app: "Safari")
    }
    let settingsA = MemorySettings()
    settingsA.set("pomodoro.workDuration", .number(30))
    settingsA.set("uploader.github.token", .string("ghp_example"))
    let settingsB = MemorySettings()
    settingsB.set("hotkey.palette", .string("Cmd+K"))
    let a = SyncEngine(db: dbA, api: api(), settings: settingsA)
    let b = SyncEngine(db: dbB, api: api(), settings: settingsB)

    func round() async throws {
        for engine in [a, b, a] { _ = try await engine.sync() }
    }
    try await round()
    XCTAssertEqual(try Fixture.dump(dbA), try Fixture.dump(dbB))
    XCTAssertEqual(try Fixture.dump(dbA).filter { $0.hasPrefix("r ") }.count, 3, "tracker rows from both Macs, by uid")
    XCTAssertEqual(settingsA.current, settingsB.current)
    XCTAssertEqual(settingsB.leaves["pomodoro.workDuration"], .number(30), "B's first contact took A's settings")
    XCTAssertEqual(settingsB.leaves["uploader.github.token"], .string("ghp_example"))
    XCTAssertEqual(settingsA.leaves["hotkey.palette"], .string("Cmd+K"), "B's extra key reached A")

    try await dbA.write { db in try db.execute(sql: "DELETE FROM pomodoro_sessions WHERE id = 'B1'") }
    try await dbB.write { db in
        try db.execute(sql: "UPDATE pomodoro_projects SET color = '#000000' WHERE name = 'nexus'")
        try db.execute(sql: "INSERT INTO pomodoro_session_tags (session_id, tag) VALUES ('A1', 'late')")
        try db.execute(sql: "UPDATE tracker_records SET end_time = 999, duration = 899 WHERE app = 'Safari'")
    }
    settingsB.set("pomodoro.workDuration", .number(40))
    try await round()
    let rows = try Fixture.dump(dbA)
    XCTAssertEqual(rows, try Fixture.dump(dbB))
    XCTAssertFalse(rows.contains { $0.hasPrefix("s B1 ") })
    XCTAssertTrue(rows.contains("p nexus #000000 1"))
    XCTAssertTrue(rows.contains("st A1 late"))
    XCTAssertTrue(rows.contains { $0.hasPrefix("r ") && $0.contains(" 200 999 899 Safari ") })
    XCTAssertEqual(settingsA.current, settingsB.current)
    XCTAssertEqual(settingsA.leaves["pomodoro.workDuration"], .number(40))
    XCTAssertEqual(try Fixture.outbox(dbA), [])
    XCTAssertEqual(try Fixture.outbox(dbB), [])
}
