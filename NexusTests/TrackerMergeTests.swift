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

    func testAGapLongerThanAFewPollsStartsANewRecord() {
        var last = record("Code", file: "a.swift")
        last.endTime = Date(timeIntervalSince1970: 1_761_800_000)
        let next = record("Code", file: "a.swift")
        XCTAssertTrue(TrackerService.canExtend(last, with: next, at: last.endTime.addingTimeInterval(5), pollInterval: 5))
        XCTAssertTrue(TrackerService.canExtend(last, with: next, at: last.endTime.addingTimeInterval(15), pollInterval: 5))
        XCTAssertFalse(TrackerService.canExtend(last, with: next, at: last.endTime.addingTimeInterval(16), pollInterval: 5), "idle or sleep in between")
        XCTAssertFalse(TrackerService.canExtend(last, with: next, at: last.endTime.addingTimeInterval(8 * 3600), pollInterval: 5))
        XCTAssertFalse(TrackerService.canExtend(last, with: record("Xcode", file: "a.swift"), at: last.endTime.addingTimeInterval(5), pollInterval: 5))
    }

    func testLockScreenIsNotActivity() {
        XCTAssertTrue(TrackerService.lockScreenBundleIds.contains("com.apple.loginwindow"))
    }

    func testEditorTitleTakesTheFolderNotTheProfile() {
        XCTAssertEqual(ContextEnricher.parseEditorTitle("01-nexus-arch.md — cpu-personal (Workspace) — Lightweight").project, "cpu-personal")
        XCTAssertEqual(ContextEnricher.parseEditorTitle("01-nexus-arch.md — cpu-personal (Workspace) — Lightweight").file, "01-nexus-arch.md")
        XCTAssertEqual(ContextEnricher.parseEditorTitle("main.swift — nexus").project, "nexus")
        XCTAssertEqual(ContextEnricher.parseEditorTitle("● main.swift — nexus [SSH: devcloud]").file, "main.swift")
        XCTAssertEqual(ContextEnricher.parseEditorTitle("main.swift — nexus [SSH: devcloud]").project, "nexus [SSH: devcloud]")
        XCTAssertEqual(ContextEnricher.parseEditorTitle("Welcome").file, "Welcome")
        XCTAssertNil(ContextEnricher.parseEditorTitle("Welcome").project)
    }
}
