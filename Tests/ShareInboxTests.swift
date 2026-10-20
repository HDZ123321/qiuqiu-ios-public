import XCTest
@testable import HermesCore

final class ShareInboxTests: XCTestCase {
    func testAtomicRoundTripOnlyExplicitAcknowledgementRemovesItem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try ShareInbox(container: root)
        let attachment = try ChatAttachment(name: "sample.txt", mime: "text/plain", data: Data("untrusted fixture".utf8))
        let id = try inbox.save(text: "https://example.org", files: [attachment])
        XCTAssertEqual(try inbox.list().map(\.id), [id])
        let item = try inbox.load(id)
        XCTAssertEqual(item.text, "https://example.org")
        XCTAssertEqual(item.files, [attachment])
        XCTAssertEqual(try inbox.list().count, 1, "preview/cancel must retain bytes")
        try inbox.remove(id)
        XCTAssertTrue(try inbox.list().isEmpty)
    }
}
