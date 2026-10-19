import XCTest
@testable import HermesCore
@testable import HermesTransport

final class ConversationFilesTests: XCTestCase {
    @MainActor func testFileBrowsingJumpPreservesPendingRunAndRejectsChangedConnection() throws {
        var running = Chat()
        running.run = try PendingRun(input: "fixture", model: "fixture", sessionID: nil, history: [], replyID: UUID())
        var reply = ChatMessage(role: "assistant", content: "source")
        reply.artifactRunID = "run_source"
        let history = Chat(messages: [reply])
        let source = try XCTUnwrap(ConversationFiles.sources(in: history).first)
        let store = ChatStore(initialChats: [running, history], save: { _ in })
        let settings = store.settings
        XCTAssertEqual(try store.locateFileSource(source, settings: settings), reply.id)
        XCTAssertEqual(store.selected, history.id)
        XCTAssertEqual(store.activeRun?.key, running.run?.key)
        XCTAssertEqual(store.activeRun?.body, running.run?.body)
        XCTAssertFalse(store.canSend)
        store.settings.bearer = "changed-synthetic-scope"
        XCTAssertThrowsError(try store.locateFileSource(source, settings: settings))
        XCTAssertEqual(store.activeRun?.key, running.run?.key)
    }

    func testArtifactDedupKeepsVerifiedMessageAndMissingTargetFailsClosed() throws {
        var reply = ChatMessage(role: "assistant", content: "fixture")
        reply.artifactRunID = "run_real"
        let chat = Chat(messages: [reply])
        let source = try XCTUnwrap(ConversationFiles.sources(in: chat).first)
        let artifact = try JSONDecoder().decode(ReplyArtifact.self, from: Data(("{\"id\":\"" + String(repeating: "a", count: 64) + "\",\"name\":\"报告.txt\",\"mime\":\"text/plain\"}").utf8))
        var index = ConversationFiles.Index()
        index.append([artifact, artifact], from: source)
        index.append([artifact], from: source)
        XCTAssertEqual(index.items.count, 1)
        XCTAssertEqual(index.items.first?.source.messageID, reply.id)
        XCTAssertTrue(ConversationFiles.canJump(source, in: [chat]))
        var missing = chat; missing.messages = []
        XCTAssertFalse(ConversationFiles.canJump(source, in: [missing]))
        var wrong = chat; wrong.id = UUID()
        XCTAssertFalse(ConversationFiles.canJump(source, in: [wrong]))
    }

    func testEmptyAndUnmappedConversationNeverInventFileSources() {
        XCTAssertTrue(ConversationFiles.sources(in: Chat()).isEmpty)
        let old = Chat(messages: [ChatMessage(role: "assistant", content: "MEDIA:/home/private/report.pdf")])
        XCTAssertTrue(ConversationFiles.sources(in: old).isEmpty)
    }

    func testOnlyExplicitAssistantRunProvenanceNotPathsOrUploads() {
        var reply = ChatMessage(role: "assistant", content: "MEDIA:/synthetic/report.txt")
        reply.artifactRunID = "run_real"
        var upload = ChatMessage(role: "user", content: "MEDIA:/synthetic/upload.txt")
        upload.artifactRunID = "run_other"
        let unknown = ChatMessage(role: "assistant", content: "MEDIA:/synthetic/unknown.txt")
        let chat = Chat(messages: [reply, upload, unknown, reply])
        let sources = ConversationFiles.sources(in: chat)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.messageID, reply.id)
        XCTAssertEqual(sources.first?.runID, "run_real")
    }
}
