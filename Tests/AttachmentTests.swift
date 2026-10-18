import XCTest
@testable import HermesCore
@testable import HermesTransport

final class AttachmentTests: XCTestCase {
    func testOversizedAttachmentReportsSizeNotFilename() {
        XCTAssertThrowsError(try ChatAttachment(name: "valid.txt", mime: "text/plain", data: Data(repeating: 65, count: 4*1024*1024+1))) { error in
            XCTAssertTrue(error.localizedDescription.contains("4194305"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("4194304"), error.localizedDescription)
            XCTAssertFalse(error.localizedDescription.contains("名称"), error.localizedDescription)
        }
    }

    func testProviderUnicodeBasenameRemainsSendable() throws {
        let long = String(repeating:"研究", count:40) + ".txt"
        let local = try ChatAttachment.localName(long, mime:"text/plain")
        XCTAssertLessThanOrEqual(local.utf8.count,180)
        XCTAssertEqual((local as NSString).pathExtension,"txt")
        XCTAssertNoThrow(try ChatAttachment(name:local,mime:"text/plain",data:Data("fixture".utf8)))
        XCTAssertThrowsError(try ChatAttachment(name:long,mime:"text/plain",data:Data("fixture".utf8)))
        XCTAssertThrowsError(try ChatAttachment.localName("bad.txt",mime:"image/jpeg"))
    }
    func testFailureReasonsAndLogsNeverContainUserData() throws {
        for (name,data,reason) in [("",Data([1]),AttachmentFailure.Reason.filenameEmpty),("../SECRET.txt",Data([1]),.filenameInvalid),("valid.txt",Data(),.emptyData)] {
            XCTAssertThrowsError(try ChatAttachment(name:name,mime:"text/plain",data:data)) { error in
                XCTAssertEqual((error as? AttachmentFailure)?.reason,reason)
                XCTAssertFalse(error.localizedDescription.contains("SECRET"))
            }
        }
        XCTAssertThrowsError(try AttachmentFailure.validateMessage(count:5,bytes:1)) { XCTAssertEqual(($0 as? AttachmentFailure)?.reason,.messageCount) }
        XCTAssertThrowsError(try AttachmentFailure.validateMessage(count:2,bytes:AttachmentFailure.limit+1)) { XCTAssertEqual(($0 as? AttachmentFailure)?.reason,.messageTotal) }
        DiagnosticLog.shared.recordProviderError(NSError(domain:"NSItemProviderErrorDomain",code:42,userInfo:[NSLocalizedDescriptionKey:"SECRET/photo.heic",NSUnderlyingErrorKey:NSError(domain:NSCocoaErrorDomain,code:260,userInfo:[NSFilePathErrorKey:"SECRET/path"])]))
        DiagnosticLog.shared.recordProviderError(NSError(domain:NSCocoaErrorDomain,code:NSUserCancelledError))
        let exported = try String(contentsOf:DiagnosticLog.shared.export())
        XCTAssertFalse(exported.contains("SECRET")); XCTAssertFalse(exported.contains("valid.txt"))
        XCTAssertTrue(exported.contains("attachmentRejected"))
    }
    @MainActor func testFailedSubmissionRetainsAttachmentsAndOneIntent() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Build5Protocol.self]
        let store = ChatStore(api: HermesAPI(session: URLSession(configuration: configuration)), initialChats: [Chat()], save: { _ in }, sleep: { _ in throw CancellationError() })
        store.settings.serverURL = "https://fixture.invalid"; store.settings.bearer = "fixture"
        let failed=expectation(description:"admission failed")
        var posts = 0
        Build5Protocol.handler = { proto in
            if proto.request.url!.path == "/v1/capabilities" {
                proto.reply(200, #"{"features":{"run_submission":true,"run_status":true,"run_stop":true,"run_approval_response":true,"runs_idempotency":{"supported":true,"durable":true,"retention_seconds":86400}}}"#)
            } else { posts += 1; proto.reply(503,"unavailable"); failed.fulfill() }
        }
        defer { store.detach(); Build5Protocol.handler=nil }
        try store.addAttachment(ChatAttachment(name:"note.txt",mime:"text/plain",data:Data("actual bytes".utf8)))
        store.send("Read")
        await fulfillment(of:[failed],timeout:3)
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertEqual(store.attachments.count,1)
        let key=store.activeRun?.key
        store.send("Do not duplicate")
        XCTAssertEqual(store.activeRun?.key,key); XCTAssertEqual(posts,1)
        XCTAssertEqual(store.current?.messages.count,2)
    }

    func testAttachmentBytesPersistInExactRunIntent() throws {
        let attachment = try ChatAttachment(name: "note.txt", mime: "text/plain", data: Data("nonce-actual-content".utf8))
        let pending = try PendingRun(input: "Read", model: "hermes-agent", sessionID: nil, history: [], replyID: UUID(), attachments: [attachment])
        let saved = try JSONDecoder().decode(PendingRun.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(saved.body, pending.body)
        XCTAssertEqual(saved.key, pending.key)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved.body) as? [String: Any])
        let items = try XCTUnwrap(object["attachments"] as? [[String:String]])
        XCTAssertEqual(Data(base64Encoded: items[0]["data"]!), attachment.data)
        XCTAssertThrowsError(try ChatAttachment(name: "../note.txt", mime: "text/plain", data: attachment.data))
    }
}
