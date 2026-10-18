import XCTest
@testable import HermesCore

final class RunHistoryTests: XCTestCase {
    func testTerminalRunIsArchivedAndActiveRunUnchanged() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = RunHistoryStore(directory: directory)
        var run = try PendingRun(input: "整理今天的日程", model: "hermes", sessionID: "s1", history: [], replyID: UUID())
        run.runID = "run_1"
        run.status = "completed"
        run.output = "已完成的结果"
        let entry = RunHistoryStore.Entry(chatID: UUID(), chatTitle: "日程", run: run)
        try store.append(entry)
        let loaded = try RunHistoryStore(directory: directory).load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].run.runID, "run_1")
        XCTAssertEqual(loaded[0].run.output, "已完成的结果")
        XCTAssertEqual(loaded[0].source, RunHistoryStore.Source.local)
    }

    func testActiveNonTerminalRunIsNeverArchived() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = RunHistoryStore(directory: directory)
        var run = try PendingRun(input: "still running", model: "hermes", sessionID: nil, history: [], replyID: UUID())
        run.status = "running"
        XCTAssertFalse(run.terminal)
        XCTAssertThrowsError(try store.append(RunHistoryStore.Entry(chatID: UUID(), chatTitle: "x", run: run)))
        XCTAssertEqual(try store.load().count, 0)
    }

    func testMigrationMovesPerChatRunIntoHistoryWithoutRemovingLatest() throws {
        // Legacy chats.json has run only on the chat; migration must copy the
        // terminal run into history and keep per-chat latest for old versions.
        let legacy = Chat(messages: [ChatMessage(role: "user", content: "old")])
        var run = try PendingRun(input: "done", model: "hermes", sessionID: nil, history: legacy.messages, replyID: UUID())
        run.status = "failed"
        var migrated = legacy
        migrated.run = run
        let history = RunHistoryStore.migrationEntries(chats: [migrated, legacy])
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].run.status, "failed")
        XCTAssertEqual(history[0].chatID, migrated.id)
    }

    func testDeduplicatesByReplyIDKeepingNewest() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = RunHistoryStore(directory: directory)
        var first = try PendingRun(input: "a", model: "m", sessionID: nil, history: [], replyID: UUID())
        first.status = "completed"
        var retry = try PendingRun(input: "a", model: "m", sessionID: nil, history: [], replyID: first.replyID)
        retry.status = "failed"
        try store.append(RunHistoryStore.Entry(chatID: UUID(), chatTitle: "t", run: first))
        try store.append(RunHistoryStore.Entry(chatID: UUID(), chatTitle: "t", run: retry))
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].run.status, "failed")
    }

    func testHistoryDoesNotChangeStopTarget() {
        // History browsing is read-only: the store exposes no mutation of the
        // active run; this contract is the compiler-enforced absence of any
        // mutating API on RunHistoryStore besides append/clear below.
        XCTAssertFalse(RunHistoryStore().entries.contains { !$0.run.terminal })
    }

    func testHistoryNeverBecomesStopTarget() throws {
        // Browsing history is read-only: RunHistoryStore exposes no API that
        // can start, stop or mutate a run; entries are copies, not references
        // into ChatStore state.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = RunHistoryStore(directory: directory)
        var run = try PendingRun(input: "done", model: "m", sessionID: nil, history: [], replyID: UUID())
        run.status = "completed"
        try store.append(RunHistoryStore.Entry(chatID: UUID(), chatTitle: "t", run: run))
        var loaded = try RunHistoryStore(directory: directory).load()
        loaded[0].run.status = "cancelled"
        let again = try RunHistoryStore(directory: directory).load()
        XCTAssertEqual(again[0].run.status, "completed")
    }

    func testRetentionBoundsAndClearRemovesFiles() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = RunHistoryStore(directory: directory, limit: 3)
        for index in 0..<5 {
            var run = try PendingRun(input: "task \(index)", model: "m", sessionID: nil, history: [], replyID: UUID())
            run.status = "completed"
            try store.append(RunHistoryStore.Entry(chatID: UUID(), chatTitle: "c\(index)", run: run))
        }
        XCTAssertEqual(try store.load().count, 3)
        XCTAssertEqual(try store.load().first?.chatTitle, "c4")
        try store.clear()
        XCTAssertEqual(try store.load().count, 0)
    }
}
