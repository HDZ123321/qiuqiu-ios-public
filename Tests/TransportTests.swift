import XCTest
import Foundation
@testable import HermesTransport
final class TransportTests: XCTestCase {
    @MainActor func testDurableNamedEventsUTF8ProductionTransport() async throws {
        let api = HermesAPI()
        var names: [String] = []
        var texts: [String] = []
        try await api.runEventsRequest(URLRequest(url: URL(string: "http://127.0.0.1:18765/runs")!)) { event in
            names.append(event.event); texts.append(event.data)
        }
        XCTAssertEqual(names, ["tool.started", "message.interim", "run.completed"])
        XCTAssertTrue(texts.last?.contains("最终🌕") == true)
    }
    func testFoundationLinesDropsSSEDelimiters() async throws {
        let (bytes, _) = try await URLSession.shared.bytes(from: URL(string: "http://127.0.0.1:18765/normal")!)
        var lines: [String] = []
        for try await line in bytes.lines { lines.append(line) }
        print("Foundation lines: count=\(lines.count), empty=\(lines.filter { $0.isEmpty }.count)")
        XCTAssertFalse(lines.contains(""), "Re-check Foundation behavior if this changes")
        XCTAssertTrue(lines.contains("data: [DONE]"))
    }

    @MainActor func testEmptyAndTruncatedStreamsNeverVerify() async throws {
        let api = HermesAPI()
        for path in ["empty", "truncated", "error", "badtype"] {
            var verified = false
            do {
                try await api.verifyStreamRequest(URLRequest(url: URL(string: "http://127.0.0.1:18765/\(path)")!), onVerified: { verified = true })
                XCTFail("Expected failure for \(path)")
            } catch {}
            XCTAssertFalse(verified)
        }
    }
    @MainActor func testCancellationNeverVerifies() async throws {
        let api = HermesAPI()
        var verified = false
        let task = Task {
            try await api.verifyStreamRequest(URLRequest(url: URL(string: "http://127.0.0.1:18765/slow")!), onVerified: { verified = true })
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { try await task.value; XCTFail("Cancellation must fail") } catch {}
        XCTAssertFalse(verified)
    }
    @MainActor func testRealChatVerificationCallback() async throws {
        let api = HermesAPI()
        var verified = false
        try await api.verifyStreamRequest(URLRequest(url: URL(string: "http://127.0.0.1:18765/normal")!), onVerified: { verified = true })
        XCTAssertTrue(verified)
    }
    @MainActor func testProductionURLSessionDeliversTextBeforeDone() async throws {
        let api = HermesAPI()
        var text = ""
        for path in ["normal", "crlf"] {
            text = ""
            try await api.streamRequest(URLRequest(url: URL(string: "http://127.0.0.1:18765/\(path)")!), onText: { text += $0 }, onTool: { _ in })
            XCTAssertEqual(text, "你好，球球🌕")
        }
    }
}
