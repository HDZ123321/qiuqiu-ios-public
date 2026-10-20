import XCTest
@testable import QiuQiu

@MainActor final class ShareDraftTransactionTests: XCTestCase {
    func testImportPersistenceFailureDoesNotMutateChatAndRetryDeduplicates() throws {
        let chat = Chat()
        var fail = true
        var persisted: [Chat] = []
        let store = ChatStore(initialChats: [chat], save: { values in
            if fail { throw ClientError.message("synthetic disk failure") }; persisted = values
        })
        let item = ShareInbox.Item(id: UUID(), created: Date(), text: "untrusted fixture", files: [])
        let scope = ServerSessionImport.scope(store.settings)
        XCTAssertThrowsError(try store.importSharedItem(item, chatID: chat.id, project: .defaultProject, expectedScope: scope))
        XCTAssertNil(store.chats.first?.shareDraft)
        XCTAssertNil(store.chats.first?.run)
        fail = false
        _ = try store.importSharedItem(item, chatID: chat.id, project: .defaultProject, expectedScope: scope)
        let id = try store.importSharedItem(item, chatID: nil, project: .defaultProject, expectedScope: scope)
        XCTAssertEqual(id, chat.id)
        XCTAssertEqual(store.chats.count, 1)
        XCTAssertEqual(persisted.first?.shareDraft?.text, item.text)
        XCTAssertNil(store.chats.first?.run)
        XCTAssertThrowsError(try store.importSharedItem(item, chatID: nil, project: .defaultProject, expectedScope: "stale"))
    }
    func testBusyConflictAndManualSendFailurePreserveImportedDraft() throws {
        let store = ChatStore(initialChats: [Chat()], save: { _ in })
        let item = ShareInbox.Item(id: UUID(), created: Date(), text: "share fixture", files: [])
        let scope = ServerSessionImport.scope(store.settings)
        store.busy = true
        XCTAssertThrowsError(try store.importSharedItem(item, chatID: nil, project: .defaultProject, expectedScope: scope))
        store.busy = false
        let id = try store.importSharedItem(item, chatID: nil, project: .defaultProject, expectedScope: scope)
        let other = ShareInbox.Item(id: UUID(), created: Date(), text: "do not replace", files: [])
        XCTAssertThrowsError(try store.importSharedItem(other, chatID: id, project: .defaultProject, expectedScope: scope))
        store.selected = id
        store.settings.bearer = "" // admission blocked, no network/model
        store.send(item.text, consumingShareID: item.id)
        XCTAssertEqual(store.current?.shareDraft?.id, item.id)
        XCTAssertNil(store.current?.run)
        store.updateShareDraft("edited fixture", chatID: id)
        XCTAssertEqual(store.current?.shareDraft?.text, "edited fixture")
    }
}
