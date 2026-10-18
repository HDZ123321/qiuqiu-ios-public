import XCTest
@testable import HermesCore
final class ClientTests: XCTestCase {
    func testHTTPSValidationAndPrefix() throws {
        XCTAssertThrowsError(try ServerEndpoint("http://example.invalid"))
        XCTAssertThrowsError(try ServerEndpoint("https://user:pass@example.invalid"))
        XCTAssertThrowsError(try ServerEndpoint("https://example.invalid?secret=value"))
        XCTAssertEqual(try ServerEndpoint("https://example.invalid/hermes/").url(for: "models").absoluteString, "https://example.invalid/hermes/v1/models")
        XCTAssertEqual(try ServerEndpoint("https://example.invalid/v1").url(for: "models").absoluteString, "https://example.invalid/v1/models")
    }
    func testRequestHasFullHistoryAndStream() throws {
        let messages = [ChatMessage(role: "user", content: "hello"), ChatMessage(role: "assistant", content: "hi"), ChatMessage(role: "user", content: "again")]
        let data = try JSONEncoder().encode(ChatRequest(model: "hermes", messages: messages))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual((object["messages"] as? [[String: Any]])?.count, 3)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("token"))
    }
    func testDecodeContentAndServerError() throws {
        XCTAssertEqual(try StreamDelta.decode("{\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}") , "hello")
        XCTAssertNil(try StreamDelta.decode("{\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"))
        XCTAssertThrowsError(try StreamDelta.decode("{\"error\":{\"message\":\"denied\"}}"))
    }
    func testChatPersistenceContainsNoConnectionSettings() throws {
        let chat = Chat(messages: [ChatMessage(role: "user", content: "question")])
        let data = try JSONEncoder().encode([chat])
        let restored = try JSONDecoder().decode([Chat].self, from: data)
        XCTAssertEqual(restored[0].messages[0].content, "question")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("bearer"))
        XCTAssertFalse(text.contains("serverURL"))
    }
}
