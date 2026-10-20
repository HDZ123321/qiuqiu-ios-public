import XCTest
@testable import HermesCore

final class ShareInboxTests: XCTestCase {
    func testDraftImportIsIdempotentAndDoesNotReplaceExistingDraftOrPendingIdentity() throws {
        let item = ShareInbox.Item(id: UUID(), created: Date(), text: "External untrusted text", files: [])
        var chat = Chat()
        try chat.importShare(item, scope: "fixture", expectedScope: "fixture")
        XCTAssertEqual(chat.shareDraft?.text, item.text)
        XCTAssertNil(chat.run)
        try chat.importShare(item, scope: "fixture", expectedScope: "fixture")
        let other = ShareInbox.Item(id: UUID(), created: Date(), text: "Other", files: [])
        XCTAssertThrowsError(try chat.importShare(other, scope: "fixture", expectedScope: "fixture"))
        XCTAssertThrowsError(try chat.importShare(item, scope: "changed", expectedScope: "fixture"))
        var pending = Chat()
        pending.run = try PendingRun(input: "fixture", model: "fixture", sessionID: nil, history: [], replyID: UUID())
        let key = pending.run?.key
        XCTAssertThrowsError(try pending.importShare(item, scope: "fixture", expectedScope: "fixture"))
        XCTAssertEqual(pending.run?.key, key)
    }
    func testLimitsSymlinkTamperExpiryAndCapacityFailClosed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try ShareInbox(container: root)
        try inbox.checkWritable()
        XCTAssertThrowsError(try inbox.save(text: "", files: []))
        XCTAssertThrowsError(try inbox.save(text: String(repeating: "x", count: 65537), files: []))
        let file = try ChatAttachment(name: "one.txt", mime: "text/plain", data: Data([1]))
        XCTAssertThrowsError(try inbox.save(text: "", files: Array(repeating: file, count: 5)))
        let id = try inbox.save(text: "keep", files: [file])
        let directory = root.appendingPathComponent("QiuShare-v1").appendingPathComponent(id.uuidString)
        let manifest = directory.appendingPathComponent("manifest.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        let records = try XCTUnwrap(object["files"] as? [[String: Any]])
        let opaque = try XCTUnwrap(records.first?["id"] as? String)
        let payload = directory.appendingPathComponent(opaque)
        try FileManager.default.removeItem(at: payload)
        let outside = root.appendingPathComponent("private.txt")
        try Data("must not read".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: payload, withDestinationURL: outside)
        XCTAssertThrowsError(try inbox.load(id))
        try inbox.remove(id)
        XCTAssertEqual(try String(contentsOf: outside), "must not read")
        let past = Date().addingTimeInterval(-ShareInbox.lifetime-1)
        let old = try ShareInbox(container: root, now: { past })
        let expired = try old.save(text: "expired", files: [])
        XCTAssertThrowsError(try inbox.load(expired))
        for _ in 1..<ShareInbox.maxItems { _ = try inbox.save(text: "bounded", files: []) }
        XCTAssertThrowsError(try inbox.save(text: "overflow", files: []))
        XCTAssertEqual(try inbox.list().count, ShareInbox.maxItems)
    }
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
