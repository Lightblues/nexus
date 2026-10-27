import GRDB
import XCTest
@testable import NexusSync

final class SchemaTests: XCTestCase {
    func testTrackerUidBackfillAndNewRows() throws {
        let queue = try Fixture.database { db in
            for i in 0..<20 { try Fixture.insertTracker(db, start: 1_761_530_000 + i * 10) }
        }
        try queue.write { db in
            let uids = try String.fetchAll(db, sql: "SELECT uid FROM tracker_records WHERE uid IS NOT NULL")
            XCTAssertEqual(uids.count, 20)
            XCTAssertEqual(Set(uids).count, 20)
            let uuid = try NSRegularExpression(pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
            for uid in uids { XCTAssertEqual(uuid.numberOfMatches(in: uid, range: NSRange(uid.startIndex..., in: uid)), 1, uid) }
            XCTAssertEqual(try Fixture.outbox(db), [], "backfill does not enqueue")

            try Fixture.insertTracker(db)
            let id = db.lastInsertedRowID
            XCTAssertEqual(id, 21, "the uid trigger keeps lastInsertedRowID the app reads")
            let uid = try XCTUnwrap(try String.fetchOne(db, sql: "SELECT uid FROM tracker_records WHERE id = ?", arguments: [id]))
            XCTAssertEqual(try Fixture.outbox(db), ["tracker_record \(uid)"])
        }
    }

    func testTriggersEnqueueEveryWrite() throws {
        let queue = try Fixture.database()
        try queue.write { db in
            try Fixture.insertSession(db, id: "S1", tags: ["deep"])
            try db.execute(sql: "INSERT INTO pomodoro_projects (name, color, created_at) VALUES ('nexus', '#fff', 1)")
            try db.execute(sql: "INSERT INTO pomodoro_tag_catalog (name, created_at) VALUES ('deep', 1)")
            XCTAssertEqual(try Fixture.outbox(db), ["pomodoro_project nexus", "pomodoro_session S1", "pomodoro_tag deep"])

            try db.execute(sql: "DELETE FROM sync_outbox")
            try db.execute(sql: "INSERT INTO pomodoro_session_tags (session_id, tag) VALUES ('S1', 'more')")
            XCTAssertEqual(try Fixture.outbox(db), ["pomodoro_session S1"], "changing a tag enqueues its session")

            try db.execute(sql: "DELETE FROM sync_outbox")
            try db.execute(sql: "UPDATE pomodoro_projects SET name = 'renamed' WHERE name = 'nexus'")
            XCTAssertEqual(try Fixture.outbox(db), ["pomodoro_project nexus", "pomodoro_project renamed"])

            try db.execute(sql: "DELETE FROM sync_outbox")
            try db.execute(sql: "DELETE FROM pomodoro_sessions WHERE id = 'S1'")
            XCTAssertEqual(try Fixture.outbox(db), ["pomodoro_session S1"])
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM pomodoro_session_tags"), 0)
            let gone = try RecordKind.named("pomodoro_session")!.record(id: "S1", updatedAt: 5, db: db)
            XCTAssertEqual(gone, SyncRecord(kind: "pomodoro_session", id: "S1", updatedAt: 5, deleted: true))
        }
    }

    func testOutboxTimestampTracksTheLatestEdit() throws {
        let queue = try Fixture.database()
        let before = SyncEngine.nowMs()
        try queue.write { db in try Fixture.insertSession(db, id: "S1") }
        Thread.sleep(forTimeInterval: 0.01)
        let first = try queue.read { db in try Int64.fetchOne(db, sql: "SELECT updated_at FROM sync_outbox")! }
        try queue.write { db in try db.execute(sql: "UPDATE pomodoro_sessions SET task = 'x' WHERE id = 'S1'") }
        let second = try queue.read { db in try Int64.fetchOne(db, sql: "SELECT updated_at FROM sync_outbox")! }
        XCTAssertGreaterThanOrEqual(first, before - 5)
        XCTAssertGreaterThan(second, first)
        XCTAssertLessThanOrEqual(second, SyncEngine.nowMs() + 5)
    }

    func testNoEchoWhileApplying() throws {
        let queue = try Fixture.database()
        try queue.write { db in
            let session = SyncRecord(kind: "pomodoro_session", id: "R1", updatedAt: 10, body: .object([
                "kind": .string("work"), "startTime": .number(100), "endTime": .number(200), "duration": .number(100),
                "project": .null, "task": .string("t"), "completedFully": .bool(false), "tags": .array([.string("a"), .string("b")]),
            ]))
            let tracker = SyncRecord(kind: "tracker_record", id: "u-1", updatedAt: 10, body: .object([
                "startTime": .number(1), "endTime": .number(6), "duration": .number(5), "app": .string("Safari"),
            ]))
            let project = SyncRecord(kind: "pomodoro_project", id: "p", updatedAt: 10, body: .object(["color": .string("#000"), "createdAt": .number(3)]))
            XCTAssertEqual(try SyncEngine.apply([session, tracker, project], db: db), 3)
            XCTAssertEqual(try Fixture.outbox(db), [])
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = 'applying'"))

            let back = try RecordKind.named("pomodoro_session")!.record(id: "R1", updatedAt: 10, db: db)
            XCTAssertEqual(back, session, "a record round-trips through its row")
            XCTAssertEqual(try RecordKind.named("tracker_record")!.record(id: "u-1", updatedAt: 10, db: db).body?["app"], .string("Safari"))

            XCTAssertEqual(try SyncEngine.apply([SyncRecord(kind: "pomodoro_session", id: "R1", updatedAt: 11, deleted: true)], db: db), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM pomodoro_sessions"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM pomodoro_session_tags"), 0)
            XCTAssertEqual(try Fixture.outbox(db), [])

            try Fixture.insertSession(db, id: "after")
            XCTAssertEqual(try Fixture.outbox(db), ["pomodoro_session after"], "triggers fire again once applying ends")
        }
    }

    func testApplySkipsRecordsMissingRequiredFields() throws {
        let queue = try Fixture.database()
        try queue.write { db in
            let bad = SyncRecord(kind: "pomodoro_project", id: "p", updatedAt: 1, body: .object(["color": .string("#000")]))
            XCTAssertEqual(try SyncEngine.apply([bad], db: db), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT count(*) FROM pomodoro_projects"), 0)
        }
    }

    func testSettingsFlattenRoundTrip() {
        let flat = Settings.flatten(Fixture.defaultConfig)
        XCTAssertEqual(flat["pomodoro.workDuration"], .number(25))
        XCTAssertEqual(flat["tracker.enrichApps"], .array([.string("Code"), .string("Google Chrome")]))
        XCTAssertEqual(flat["uploader.github.token"], .string(""))
        XCTAssertEqual(Settings.unflatten(flat), Fixture.defaultConfig)
    }
}
