import XCTest
@testable import HermesCore
@testable import HermesTransport

final class ServerSessionTests: XCTestCase {
    func testRealTitleAndRefreshMergePreserveLocalIdentityEditsAndDeduplicate() throws {
        let metadata = try JSONDecoder().decode(ServerSessionItem.self,from:Data(#"{"session_id":"s_a","created_seq":1,"run_count":1,"history":"explicit_fetch","title":"Native original","title_source":"native"}"#.utf8))
        let page = try JSONDecoder().decode(ServerSessionMessages.self,from:Data(#"{"session_id":"s_a","history":"stored_text","items":[{"id":"1","role":"user","content":"question"}],"next_offset":null}"#.utf8))
        let newer = try JSONDecoder().decode(ServerSessionMessages.self,from:Data(#"{"session_id":"s_a","history":"stored_text","items":[{"id":"1","role":"user","content":"question"},{"id":"2","role":"assistant","content":"latest stored answer"}],"next_offset":null}"#.utf8))
        var chats:[Chat]=[]
        let id = try ServerSessionImport.open(metadata,scope:"a",chats:&chats,pages:[page])
        XCTAssertEqual(chats[0].title,"Native original")
        let mid = chats[0].messages[0].id
        chats[0].customTitle="My edited title"
        chats[0].messages[0].content="My edited message"
        XCTAssertEqual(try ServerSessionImport.open(metadata,scope:"a",chats:&chats,pages:[newer]),id)
        XCTAssertEqual(chats.count,1)
        XCTAssertEqual(chats[0].title,"My edited title")
        XCTAssertEqual(chats[0].messages.map(\.content),["My edited message","latest stored answer"])
        XCTAssertEqual(chats[0].messages[0].id,mid)
        _ = try ServerSessionImport.open(metadata,scope:"a",chats:&chats,pages:[newer])
        XCTAssertEqual(chats[0].messages.count,2)
    }
    func testImportIsIdempotentAndNeverOverwritesLocalEdits() throws {
        let metadata = try JSONDecoder().decode(ServerSessionItem.self, from: Data(#"{"session_id":"run_owned","created_seq":1,"run_count":2,"history":"explicit_fetch"}"#.utf8))
        var chats: [Chat] = []
        let id = try ServerSessionImport.open(metadata, scope: "scope-a", chats: &chats)
        XCTAssertEqual(chats.count, 1); XCTAssertTrue(chats[0].messages.isEmpty)
        XCTAssertEqual(chats[0].sessionID, "run_owned"); XCTAssertNil(chats[0].run)
        chats[0].customTitle = "edited"
        chats[0].messages = [ChatMessage(role: "user", content: "local edit")]
        XCTAssertEqual(try ServerSessionImport.open(metadata, scope: "scope-a", chats: &chats), id)
        XCTAssertEqual(chats[0].title, "edited"); XCTAssertEqual(chats[0].messages[0].content, "local edit")
        _ = try ServerSessionImport.open(metadata, scope: "scope-b", chats: &chats)
        XCTAssertEqual(chats.count, 2)
        let restored = try JSONDecoder().decode([Chat].self, from: JSONEncoder().encode(chats))
        XCTAssertEqual(restored[0].serverSource?.scope, "scope-a")
    }
    func testOnlyEmptyImportedChatReceivesStoredHistoryWithStableIdentity() throws {
        let metadata = try JSONDecoder().decode(ServerSessionItem.self, from: Data(#"{"session_id":"s_a","created_seq":1,"run_count":1,"history":"explicit_fetch"}"#.utf8))
        let page = try JSONDecoder().decode(ServerSessionMessages.self, from: Data(#"{"session_id":"s_a","history":"stored_text","items":[{"id":"1","role":"user","content":"stored text"},{"id":"1","role":"user","content":"stored text"}],"next_offset":null}"#.utf8))
        var chats: [Chat] = []
        let id = try ServerSessionImport.open(metadata, scope: "a", chats: &chats, pages: [page])
        XCTAssertEqual(chats[0].messages.count,1)
        let mid = chats[0].messages[0].id
        _ = try ServerSessionImport.open(metadata, scope: "a", chats: &chats, pages: [page])
        XCTAssertEqual(chats[0].id,id); XCTAssertEqual(chats[0].messages[0].id,mid)
        XCTAssertEqual(chats[0].serverSource?.history,"stored_text")
        let run = try PendingRun(input:"manually sent",model:"fixture",sessionID:chats[0].sessionID,history:chats[0].messages,replyID:UUID())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:run.body) as? [String:Any])
        XCTAssertEqual(body["session_id"] as? String,"s_a"); XCTAssertNil(body["conversation_history"])
    }
    @MainActor func testImportWhileBusyPreservesStopTargetAndDoesNotSend() throws {
        var active = Chat()
        active.run = try PendingRun(input:"fixture", model:"fixture", sessionID:nil,history:[],replyID:UUID())
        let store = ChatStore(initialChats:[active],save:{ _ in })
        let item = try JSONDecoder().decode(ServerSessionItem.self,from:Data(#"{"session_id":"s_a","created_seq":1,"run_count":1,"history":"explicit_fetch"}"#.utf8))
        try store.openServerSession(item, pages:[])
        XCTAssertEqual(store.activeRun?.key,active.run?.key); XCTAssertTrue(store.busy)
        XCTAssertNil(store.current?.run); XCTAssertEqual(store.current?.sessionID,"s_a")
        store.cancel()
        XCTAssertEqual(store.chats.first(where:{$0.id==active.id})?.run?.status,"cancelled")
    }
    @MainActor func testConnectionChangeCannotSendImportedSession() throws {
        let store = ChatStore(initialChats: [Chat()], save: { _ in })
        store.settings.serverURL = "https://fixture.invalid"
        store.settings.bearer = "fixture-a"
        let item = try JSONDecoder().decode(ServerSessionItem.self,from:Data(#"{"session_id":"s_a","created_seq":1,"run_count":1,"history":"explicit_fetch"}"#.utf8))
        try store.openServerSession(item,pages:[])
        store.settings.bearer = "fixture-b"
        store.send("must not dispatch")
        XCTAssertNil(store.current?.run); XCTAssertFalse(store.busy)
        XCTAssertTrue(store.current?.messages.isEmpty == true)
        XCTAssertNotNil(store.error)
    }
    func testLegacyChatDecodesWithoutNewSource() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","messages":[],"sessionID":"legacy"}"#
        let chat = try JSONDecoder().decode(Chat.self,from:Data(json.utf8))
        XCTAssertNil(chat.serverSource); XCTAssertEqual(chat.sessionID,"legacy")
        XCTAssertNotEqual(ServerSessionImport.scope(ConnectionSettings()), "")
    }
}
