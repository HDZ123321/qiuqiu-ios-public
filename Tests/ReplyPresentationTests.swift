import XCTest
@testable import HermesCore

final class ReplyPresentationTests: XCTestCase {
    func testTablesQuotesCodeAndParagraphsKeepStructure() {
        let blocks = MessageBlock.parse("> quoted\n\n| A | B |\n| --- | --- |\n| one | two |\n\n```swift\nlet s = \"|not table|\"\n```\n\n[site](https://example.org)")
        XCTAssertEqual(blocks.map(\.kind), [.quote,.table,.code,.prose])
        XCTAssertEqual(blocks[1].rows, [["A","B"],["one","two"]])
        XCTAssertEqual(blocks[2].text, "let s = \"|not table|\"")
    }
    func testSafeLinksNeverAllowLocalFilesOrScripts() {
        XCTAssertNil(ReplyLink.external("file:///etc/hosts"))
        XCTAssertNil(ReplyLink.external("javascript:alert(1)"))
        XCTAssertNotNil(ReplyLink.external("https://example.org/report"))
        XCTAssertNil(ReplyLink.external("https://user:secret@example.org"))
    }
}
