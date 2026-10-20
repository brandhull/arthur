import XCTest
@testable import ArthurKit

/// Each case mirrors something verified against Craft's real markdown import
/// (see CraftMarkdown's header comment) — the expected blocks are what Craft
/// actually produced, not what markdown "should" do.
final class CraftMarkdownTests: XCTestCase {
    func testConsecutiveLinesStayOneParagraphWithSoftBreak() {
        XCTAssertEqual(CraftMarkdown.parse("line one\nline two"), [.paragraph("line one\nline two")])
    }

    func testBlankLinesSplitBlocks() {
        XCTAssertEqual(CraftMarkdown.parse("para A\n\npara B"), [.paragraph("para A"), .paragraph("para B")])
        XCTAssertEqual(CraftMarkdown.parse("Title\n\n\n\nafter"), [.paragraph("Title"), .paragraph("after")])
    }

    func testListItemsAreOwnBlocksWithIndentLevels() {
        XCTAssertEqual(
            CraftMarkdown.parse("head\n- a\n- b\n  - nested\n    - deeper"),
            [.paragraph("head"), .bullet(level: 0, text: "a"), .bullet(level: 0, text: "b"),
             .bullet(level: 1, text: "nested"), .bullet(level: 2, text: "deeper")]
        )
    }

    func testNumberedListIsRenumberedByPositionAndSubBullets() {
        let blocks = CraftMarkdown.parse("1. one\n1. two\n   - sub\n\ntext\n\n5. again")
        XCTAssertEqual(blocks, [
            .numbered(level: 0, text: "one"), .numbered(level: 0, text: "two"),
            .bullet(level: 1, text: "sub"), .paragraph("text"), .numbered(level: 0, text: "again")
        ])
        XCTAssertEqual(CraftMarkdown.numbering(for: blocks), [1, 2, nil, nil, 1])
    }

    func testTasks() {
        XCTAssertEqual(
            CraftMarkdown.parse("- [ ] todo\n- [x] done"),
            [.task(level: 0, done: false, text: "todo"), .task(level: 0, done: true, text: "done")]
        )
    }

    func testHeadingEndsAtItsLine() {
        XCTAssertEqual(
            CraftMarkdown.parse("# H1\ntext right after\n## H2"),
            [.heading(level: 1, text: "H1"), .paragraph("text right after"), .heading(level: 2, text: "H2")]
        )
    }

    func testDividerAndSetextHeading() {
        XCTAssertEqual(CraftMarkdown.parse("before\n\n*****\n\nafter"), [.paragraph("before"), .divider, .paragraph("after")])
        XCTAssertEqual(CraftMarkdown.parse("x\n---\ny"), [.heading(level: 2, text: "x"), .paragraph("y")])
    }

    func testQuoteLinesMergeIntoOneBlock() {
        XCTAssertEqual(CraftMarkdown.parse("> one\n> two"), [.quote("one\ntwo")])
    }

    func testPlainLineContinuesListItem() {
        XCTAssertEqual(CraftMarkdown.parse("- item\ncontinuation"), [.bullet(level: 0, text: "item\ncontinuation")])
        XCTAssertEqual(
            CraftMarkdown.parse("para\n- bullet\nmore text"),
            [.paragraph("para"), .bullet(level: 0, text: "bullet\nmore text")]
        )
    }

    func testStarBulletPlusToggleAndFencedCode() {
        XCTAssertEqual(
            CraftMarkdown.parse("* star\n+ plus\n- dash"),
            [.bullet(level: 0, text: "star"), .toggle(level: 0, text: "plus"), .bullet(level: 0, text: "dash")]
        )
        XCTAssertEqual(CraftMarkdown.parse("```\nl1\nl2\n```"), [.code("l1\nl2")])
    }

    func testQuickCaptureSeparatorSuffix() {
        // Quick Capture appends a blank line and "*****" when Add Separator is on.
        XCTAssertEqual(CraftMarkdown.parse("note text\n\n*****"), [.paragraph("note text"), .divider])
    }
}
