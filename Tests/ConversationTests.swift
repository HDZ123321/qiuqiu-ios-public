import XCTest
@testable import HermesCore
@testable import HermesTransport

final class ConversationTests: XCTestCase {
    func testPinnedArchivedMetadataSurvivesRoundTrip() throws {
        let chat = Chat()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(chat)) as? [String: Any])
        object["pinned"] = true; object["archived"] = true
        let restored = try JSONDecoder().decode(Chat.self, from: JSONSerialization.data(withJSONObject: object))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        XCTAssertEqual(encoded["pinned"] as? Bool, true)
        XCTAssertEqual(encoded["archived"] as? Bool, true)
    }
    @MainActor func testReadOnlySelectionDoesNotRedirectActiveTaskOrStop() throws {
        var running = Chat()
        running.run = try PendingRun(input: "fixture", model: "hermes", sessionID: nil, history: [], replyID: UUID())
        let other = Chat(messages: [ChatMessage(role: "user", content: "历史")])
        let store = ChatStore(initialChats: [running, other], save: { _ in })
        store.selected = other.id
        XCTAssertEqual(store.activeRun?.key, running.run?.key)
        XCTAssertFalse(store.canSend)
        store.cancel()
        XCTAssertEqual(store.chats.first?.run?.status, "cancelled")
        XCTAssertEqual(store.current?.id, other.id)
    }
    @MainActor func testSearchAndManagementPersistWithoutTouchingRunIntent() throws {
        var a = Chat(messages: [ChatMessage(role: "user", content: "Swift方案")])
        a.run = try PendingRun(input: "fixture", model: "hermes", sessionID: nil, history: [], replyID: UUID())
        let b = Chat(messages: [ChatMessage(role: "assistant", content: "后台恢复")])
        var saved: [Chat] = []
        let store = ChatStore(initialChats: [a, b], save: { saved = $0 })
        store.rename(a.id, title: "  项目 A  "); store.togglePin(b.id)
        XCTAssertEqual(store.conversations(query: "swift").map(\.id), [a.id])
        XCTAssertEqual(store.conversations(query: "项目").map(\.id), [a.id])
        XCTAssertEqual(store.conversations().first?.id, b.id)
        store.toggleArchive(a.id)
        XCTAssertFalse(store.chats.first?.archived == true, "running chat cannot be archived")
        store.toggleArchive(b.id)
        XCTAssertTrue(store.conversations().allSatisfy { $0.id != b.id })
        XCTAssertEqual(store.conversations(query: "恢复", archived: true).first?.id, b.id)
        XCTAssertEqual(saved.first?.title, "项目 A")
        XCTAssertEqual(saved.first?.run?.key, a.run?.key)
        XCTAssertEqual(saved.first?.run?.body, a.run?.body)
        store.rename(a.id, title: " ")
        XCTAssertEqual(store.chats.first?.title, "Swift方案")
    }
    func testMarkdownFencesPreserveCodeAndUnclosedDraft() {
        let blocks = MessageBlock.parse("# 标题\n\n```swift\nlet n = 1\n```\n结束\n~~~sh\necho ok")
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[1].language, "swift")
        XCTAssertEqual(blocks[1].text, "let n = 1")
        XCTAssertEqual(blocks[3].language, "sh")
        XCTAssertEqual(blocks[3].text, "echo ok")
    }
    func testStoredCustomTitleOverridesGeneratedTitle() throws {
        let chat = Chat(messages: [ChatMessage(role: "user", content: "原来的问题")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(chat)) as? [String: Any])
        object["customTitle"] = "  我的项目  "
        let restored = try JSONDecoder().decode(Chat.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.title, "我的项目")
        XCTAssertEqual(restored.messages.first?.content, "原来的问题")
    }
}
