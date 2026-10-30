import XCTest
@testable import Nexus

@MainActor
final class PaletteSearchTests: XCTestCase {
    private func command(_ id: String, title: String, group: String? = nil, keywords: [String] = [], subtitle: String? = nil) -> Command {
        Command(id: id, title: title, group: group, keywords: keywords, subtitle: { subtitle }, run: {})
    }

    private func ids(_ commands: [Command], _ query: String) -> [String] {
        PaletteSearch.score(commands, query: query).map(\.id)
    }

    func testEmptyQueryReturnsTheInputUnchanged() {
        let all = [command("b", title: "Beta"), command("a", title: "Alpha"), command("c", title: "Other")]
        XCTAssertEqual(ids(all, ""), ["b", "a", "c"])
        XCTAssertEqual(ids(all, "  \n"), ["b", "a", "c"])
    }

    func testTitleOutranksGroupOutranksKeywordsOutranksSubtitle() {
        let all = [
            command("subtitle", title: "One", subtitle: "zap"),
            command("keyword", title: "Two", keywords: ["zap"]),
            command("group", title: "Three", group: "zap"),
            command("title", title: "zap"),
        ]
        XCTAssertEqual(ids(all, "zap"), ["title", "group", "keyword", "subtitle"])
    }

    func testNonMatchesAreDroppedAndCaseIsIgnored() {
        let all = [command("a", title: "Start Pomodoro"), command("b", title: "Upload Image")]
        XCTAssertEqual(ids(all, "POMO"), ["a"])
        XCTAssertEqual(ids(all, "qqq"), [])
    }

    func testPrefixBeatsMidStringBeatsSubsequence() {
        let all = [
            command("subsequence", title: "s-t-a-r-t"),
            command("middle", title: "Quick start"),
            command("prefix", title: "Start timer"),
        ]
        XCTAssertEqual(ids(all, "start"), ["prefix", "middle", "subsequence"])
    }

    func testEqualScoresKeepInsertionOrder() {
        let all = [command("first", title: "Open"), command("second", title: "Open"), command("third", title: "Open")]
        XCTAssertEqual(ids(all, "open"), ["first", "second", "third"])
    }
}
