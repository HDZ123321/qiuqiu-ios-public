import XCTest
@testable import HermesCore
@testable import HermesTransport

final class ServerSessionSyncTests: XCTestCase {
    private func page(_ json: String) throws -> ServerSessionMessages {
        try JSONDecoder().decode(ServerSessionMessages.self, from: Data(json.utf8))
    }
    func testMergeAppendsOnlyNewRowsAndNeverDuplicates() throws {
        var chat = Chat()
        var first = ChatMessage(role: "user", content: "question")
        first.serverMessageID = "1"
        chat.messages = [first]
        let older = try page(#"{"session_id":"s_a","history":"stored_text","items":[{"id":"1","role":"user","content":"question"},{"id":"2","role":"assistant","content":"stored answer"}],"next_offset":null}"#)
        ServerSessionSyncEngine.merge(older, into: &chat)
        XCTAssertEqual(chat.messages.map(\.content), ["question", "stored answer"])
        XCTAssertEqual(chat.messages.map(\.serverMessageID), ["1", "2"])
        // Re-merge same page and a page containing both again: no duplicates.
        ServerSessionSyncEngine.merge(older, into: &chat)
        let full = try page(#"{"session_id":"s_a","history":"stored_text","items":[{"id":"1","role":"user","content":"question"},{"id":"2","role":"assistant","content":"stored answer"},{"id":"3","role":"assistant","content":"finalized follow-up"}],"next_offset":null}"#)
        ServerSessionSyncEngine.merge(full, into: &chat)
        XCTAssertEqual(chat.messages.map(\.content), ["question", "stored answer", "finalized follow-up"])
        XCTAssertEqual(chat.messages.count, 3)
    }
    func testMergeNeverOverwritesLocalEditOfSameServerID() throws {
        var chat = Chat()
        var local = ChatMessage(role: "user", content: "my edited text")
        local.serverMessageID = "1"
        chat.messages = [local]
        let page = try page(#"{"session_id":"s_a","history":"stored_text","items":[{"id":"1","role":"user","content":"stored original"}],"next_offset":null}"#)
        ServerSessionSyncEngine.merge(page, into: &chat)
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertEqual(chat.messages[0].content, "my edited text")
    }
    func testMergeIgnoresUnavailableHistoryAndNonUserAssistantRows() throws {
        var chat = Chat()
        let unavailable = try page(#"{"session_id":"s_a","history":"unavailable","items":[],"next_offset":null}"#)
        ServerSessionSyncEngine.merge(unavailable, into: &chat)
        XCTAssertTrue(chat.messages.isEmpty)
        let withTool = try page(#"{"session_id":"s_a","history":"stored_text","items":[{"id":"9","role":"tool","content":"secret tool output"}],"next_offset":null}"#)
        ServerSessionSyncEngine.merge(withTool, into: &chat)
        XCTAssertTrue(chat.messages.isEmpty)
    }
    func testSyncSnapshotDecodesBusyAndFreeStates() throws {
        let busy = try JSONDecoder().decode(ServerSessionSync.self, from: Data(#"{"session_id":"s_a","channel_active":true,"server_state":"running","last_checked":1,"can_continue":false}"#.utf8))
        XCTAssertTrue(busy.busyOnServer); XCTAssertFalse(busy.can_continue)
        let free = try JSONDecoder().decode(ServerSessionSync.self, from: Data(#"{"session_id":"s_a","channel_active":false,"server_state":"completed","last_checked":2,"can_continue":true}"#.utf8))
        XCTAssertFalse(free.busyOnServer); XCTAssertTrue(free.can_continue)
    }
    @MainActor func testSyncDoesNotTouchPendingRunAndMarksBusyWithoutSending() async throws {
        let store = ChatStore(initialChats: [], save: { _ in })
        var chat = Chat()
        chat.sessionID = "s_a"
        chat.serverSource = ServerSessionSource(scope: ServerSessionImport.scope(store.settings), history: "stored_text")
        let run = try PendingRun(input: "local pending", model: "fixture", sessionID: "s_a", history: [], replyID: UUID())
        chat.run = run
        store.chats = [chat]; store.selected = chat.id; store.foreground = true
        await store.syncOnce(chatID: chat.id)
        XCTAssertEqual(store.syncState[chat.id], "stale")
        XCTAssertEqual(store.chats[0].run?.key, run.key) // stop/task identity untouched
        XCTAssertEqual(store.chats[0].messages.count, 0) // no injection into active task
    }
}
