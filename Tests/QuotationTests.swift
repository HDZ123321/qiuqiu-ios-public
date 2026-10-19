import XCTest
@testable import HermesCore

final class QuotationTests: XCTestCase {
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
