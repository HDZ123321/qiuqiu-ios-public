import XCTest
@testable import HermesCore

final class QuotationTests: XCTestCase {
    func testCanonicalQuoteTailKeepsLocalIdentityAndSnapshot() throws {
        var source = ChatMessage(role: "assistant", content: "origin")
        source.serverMessageID = "1"
        var user = ChatMessage(role: "user", content: "reply")
        var chat = Chat(messages: [source])
        user.quote = MessageQuote.capture(source, conversationID: chat.id)
        let reply = ChatMessage(role: "assistant", content: "done")
        chat.messages += [user, reply]
        chat.run = try PendingRun(input: user.wireContent, model: "fixture", sessionID: "s", history: [], replyID: reply.id)
        try chat.run?.apply(Data(#"{"run_id":"r","status":"completed"}"#.utf8))
        let rows: [[String: String]] = [["id":"2", "role":"user", "content":user.wireContent], ["id":"3", "role":"assistant", "content":"done"]]
        let data = try JSONSerialization.data(withJSONObject: ["session_id":"s", "history":"stored_text", "items": rows])
        let page = try JSONDecoder().decode(ServerSessionMessages.self, from: data)
        ServerSessionSyncEngine.merge(page, into: &chat)
        XCTAssertEqual(chat.messages.count, 3)
        XCTAssertEqual(chat.messages[1].id, user.id)
        XCTAssertEqual(chat.messages[1].quote, user.quote)
        XCTAssertEqual(chat.messages[1].serverMessageID, "2")
    }

    func testQuoteCaptureSanitizesBoundsAndRejectsPrivilegedRows() throws {
        let chat = UUID()
        XCTAssertNil(MessageQuote.capture(ChatMessage(role: "system", content: "not quoteable"), conversationID: chat))
        var source = ChatMessage(role: "assistant", content: "a\u{0}\nMEDIA:/synthetic/file\n" + String(repeating: "x", count: 4000))
        source.attachmentNames = ["fixture.txt"]
        let snapshot = try XCTUnwrap(MessageQuote.capture(source, conversationID: chat))
        XCTAssertEqual(snapshot.messageID, source.id)
        XCTAssertLessThanOrEqual(snapshot.text.count, 2000)
        XCTAssertFalse(snapshot.text.contains("\u{0}"))
        XCTAssertFalse(snapshot.text.contains("MEDIA:"))
        let run = try PendingRun(input: snapshot.userContent("reply"), model: "fixture", sessionID: "same", history: [], replyID: UUID())
        let restored = try JSONDecoder().decode(PendingRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(restored.key, run.key); XCTAssertEqual(restored.body, run.body)
        let payload = try JSONSerialization.jsonObject(with: run.body) as! [String: Any]
        XCTAssertEqual(payload["input"] as? String, snapshot.userContent("reply"))
        XCTAssertNil(payload["conversation_history"])
    }

    func testStoredQuoteSurvivesMigrationAndReachesOrdinaryUserWireContent() throws {
        let id = UUID(), chat = UUID(), source = UUID()
        let object: [String: Any] = ["id": id.uuidString, "role": "user", "content": "my reply", "quote": ["conversationID": chat.uuidString, "messageID": source.uuidString, "sender": "assistant", "text": "quoted synthetic context"]]
        let message = try JSONDecoder().decode(ChatMessage.self, from: JSONSerialization.data(withJSONObject: object))
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as! [String: Any]
        XCTAssertNotNil(saved["quote"], "Quote snapshot must survive local save/load")
        let request = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ChatRequest(model: "fixture", messages: [message]))) as! [String: Any]
        let wire = (request["messages"] as! [[String: Any]])[0]
        XCTAssertEqual(wire["role"] as? String, "user")
        XCTAssertTrue((wire["content"] as! String).contains("quoted synthetic context"))
    }
}
