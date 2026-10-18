import XCTest
@testable import HermesCore

final class MessageTypographyTests: XCTestCase {
    func testHeadingHierarchyAndNestedHangingListContent() {
        let b = MessageBlock.parse("# Title\nBody\n1. First\n   continuation\n  - Nested\n- [x] Finished\n###### Deep")
        XCTAssertEqual(b.map(\.text), ["Title", "Body", "First\ncontinuation", "Nested", "Finished", "Deep"])
        XCTAssertEqual(b.map(\.kind), [.heading,.prose,.listItem,.listItem,.listItem,.heading])
        XCTAssertEqual(b[3].level, 1); XCTAssertEqual(b[4].checked, true); XCTAssertEqual(b[5].level, 3)
    }
    func testTableEscapesCodeSpansAlignmentAndRawCopy() {
        let raw = "| A | B |\n| :--- | ---: |\n| a\\|b | `x|y` |"
        let b = MessageBlock.parse(raw)
        XCTAssertEqual(b.first?.rows, [["A","B"],["a\\|b","`x|y`"]])
        XCTAssertEqual(b.first?.alignments, [.leading,.trailing]); XCTAssertEqual(b.first?.text, raw)
    }
    func testMalformedTableRemainsVisibleProse() {
        for raw in ["a|b\n---", "a|b\n---|bad", "a\\|b\n---|---", "a|b\n---|---|---"] {
            XCTAssertEqual(MessageBlock.parse(raw).map(\.text).joined(separator: "\n"), raw)
            XCTAssertFalse(MessageBlock.parse(raw).contains { $0.kind == .table })
        }
    }
    func testLongFencePreservesShortFenceAndWhitespace() {
        XCTAssertEqual(MessageBlock.parse("````swift\n  a\n\n```\nb\n\n````").first?.text, "  a\n\n```\nb\n")
    }
    func testStreamingUnclosedFenceDoesNotLoseTailOrIdentity() {
        let prefixes = ["```swift\n", "```swift\n  a", "```swift\n  a\n", "```swift\n  a\n\n"]
        for raw in prefixes {
            let b = MessageBlock.parse(raw)
            XCTAssertEqual(b.count, 1); XCTAssertEqual(b.first?.id, 0)
            XCTAssertEqual(b.first?.text, String(raw.dropFirst("```swift\n".count)))
        }
    }
    func testQuoteInlineAndParagraphBreaksRemain() {
        XCTAssertEqual(MessageBlock.parse("> **bold**\n>\n> [link](https://example.org)").first?.text, "**bold**\n\n[link](https://example.org)")
        XCTAssertEqual(MessageBlock.parse("- [ ] Pending").first?.checked, false)
        XCTAssertEqual(MessageBlock.parse("#not heading").first?.kind, .prose)
    }
    func testOnlyUserScrollChangesFollowState() {
        var state = MessageReadPosition()
        state.contentChanged(); XCTAssertTrue(state.following)
        state.userScrolled(distanceFromBottom: 300); state.contentChanged()
        XCTAssertFalse(state.following); XCTAssertTrue(state.hasNewContent)
        state.userScrolled(distanceFromBottom: 20)
        XCTAssertTrue(state.following); XCTAssertFalse(state.hasNewContent)
    }
}
