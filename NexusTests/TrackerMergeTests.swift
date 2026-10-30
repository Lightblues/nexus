import XCTest
@testable import Nexus

final class TrackerMergeTests: XCTestCase {
    private func record(_ app: String, file: String? = nil, project: String? = nil, title: String? = nil) -> WindowActivityRecord {
        let now = Date(timeIntervalSince1970: 1_761_800_000)
        let context = file == nil && project == nil ? nil : ActivityContext(project: project, file: file)
        return WindowActivityRecord(startTime: now, endTime: now, duration: 0, app: app, bundleId: nil, title: title, context: context)
    }

    func testSameAppAndFileMerges() {
        XCTAssertTrue(TrackerService.isSameActivity(record("Code", file: "a.swift"), record("Code", file: "a.swift")))
        XCTAssertTrue(TrackerService.isSameActivity(record("Finder"), record("Finder")))
    }

    func testOnlyAppAndFileAreTheKey() {
        XCTAssertTrue(TrackerService.isSameActivity(record("Code", file: "a.swift", project: "x", title: "one"),
                                                    record("Code", file: "a.swift", project: "y", title: "two")))
    }

    func testDifferentAppDoesNotMerge() {
        XCTAssertFalse(TrackerService.isSameActivity(record("Code", file: "a.swift"), record("Xcode", file: "a.swift")))
    }

    func testDifferentFileDoesNotMerge() {
        XCTAssertFalse(TrackerService.isSameActivity(record("Code", file: "a.swift"), record("Code", file: "b.swift")))
        XCTAssertFalse(TrackerService.isSameActivity(record("Code", file: "a.swift"), record("Code")))
    }
}
