import XCTest
@testable import HermesCore

final class RunTests: XCTestCase {
    func testLegacyChatMigrationAndPendingRoundTrip() throws {
        let chat = Chat(messages: [ChatMessage(role: "user", content: "old")])
        let data = try JSONEncoder().encode(chat)
        var migrated = try JSONDecoder().decode(Chat.self, from: data)
        XCTAssertNil(migrated.run)
        migrated.run = try PendingRun(input: "new", model: "hermes-agent", sessionID: nil, history: migrated.messages, replyID: UUID())
        let saved = try JSONDecoder().decode(Chat.self, from: JSONEncoder().encode(migrated))
        XCTAssertEqual(saved.run?.key, migrated.run?.key)
        XCTAssertEqual(saved.run?.body, migrated.run?.body)
    }
    func testExactApprovalAndStoppingRemainNonterminal() throws {
        var run = try PendingRun(input: "hi", model: "hermes-agent", sessionID: nil, history: [], replyID: UUID())
        try run.apply(Data(#"{"run_id":"run_a","status":"waiting_for_approval","approval":{"request_id":"exact-1","command":"read-only check","choices":["once","deny"]}}"#.utf8))
        XCTAssertEqual(run.approval?.request_id, "exact-1")
        XCTAssertEqual(run.approval?.choices, ["once", "deny"])
        try run.apply(Data(#"{"run_id":"run_a","status":"stopping"}"#.utf8))
        XCTAssertFalse(run.terminal)
        XCTAssertNil(run.approval)
        XCTAssertThrowsError(try run.apply(Data(#"{"run_id":"run_OTHER","status":"completed"}"#.utf8)))
        try run.apply(Data(#"{"run_id":"run_a","status":"interrupted"}"#.utf8))
        XCTAssertTrue(run.terminal)
        XCTAssertNotEqual(run.status, "completed")
    }
    func testFinalOutputReplacesInterimAndTerminalIsMonotonic() throws {
        var run = try PendingRun(input: "hi", model: "hermes-agent", sessionID: nil, history: [], replyID: UUID())
        try run.apply(Data(#"{"run_id":"run_a","status":"running","session_id":"s"}"#.utf8))
        try run.apply(Data(#"{"run_id":"run_a","status":"completed","output":"最终答案"}"#.utf8))
        try run.apply(Data(#"{"run_id":"run_a","status":"running"}"#.utf8))
        XCTAssertEqual(run.status, "completed")
        XCTAssertEqual(run.output, "最终答案")
        XCTAssertEqual(run.sessionID, "s")
        XCTAssertTrue(run.terminal)
    }
}
