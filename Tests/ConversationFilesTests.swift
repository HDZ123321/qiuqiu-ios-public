import XCTest
@testable import HermesCore

final class ConversationFilesTests: XCTestCase {
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
