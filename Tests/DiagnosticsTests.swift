import XCTest
import Foundation
@testable import HermesCore
final class DiagnosticsTests: XCTestCase {
    func testLogsExcludeSecretsAndRotateOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory, limit: 1024)
        for _ in 0..<100 { log.record(.requestStart, id: UUID(), url: URL(string: "https://user:password@example.org/v1/chat/completions?token=SECRET")) }
        let text = try String(contentsOf: log.export())
        XCTAssertFalse(text.contains("SECRET")); XCTAssertFalse(text.contains("password")); XCTAssertFalse(text.contains("user:"))
        XCTAssertFalse(text.contains("?token")); XCTAssertTrue(text.contains("example.org/v1/chat/completions"))
        for name in ["current.log", "previous.log"] {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            XCTAssertLessThanOrEqual(data.count, 1024)
        }
        log.clear()
        XCTAssertFalse(try String(contentsOf: log.export()).contains("example.org"))
    }
    func testTypedLifecycleRoutesAndHonestSummary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory)
        XCTAssertEqual(DiagnosticLog.route("runs/run_secret/stop"), .stop)
        XCTAssertEqual(DiagnosticLog.route("runs/run_secret/events"), .events)
        log.record(.send, id: UUID())
        log.record(.runState, state: .completed)
        let report = try String(contentsOf: log.export())
        XCTAssertTrue(report.contains("发送：已观察"))
        XCTAssertTrue(report.contains("真实批准请求：未观察/未验证"))
        XCTAssertFalse(report.contains("run_secret"))
    }
    func testVerificationRejectsStaleAndInvalidatedCallbacks() {
        var state = ConnectionVerification()
        let first = state.begin()
        state.invalidate()
        XCTAssertFalse(state.complete(first))
        let second = state.begin()
        state.authenticated(second)
        XCTAssertEqual(state.phase, .authenticated)
        XCTAssertFalse(state.complete(first))
        XCTAssertTrue(state.complete(second))
        XCTAssertEqual(state.phase, .verified)
        state.fail(second)
        XCTAssertEqual(state.phase, .failed)
    }
}
