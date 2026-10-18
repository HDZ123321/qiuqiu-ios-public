import XCTest
@testable import HermesCore
final class CoreTests: XCTestCase {
    func testByteFramingPreservesUTF8AndAllNewlines() {
        for newline in ["\n", "\r\n", "\r"] {
            let input = ": ping\(newline)\(newline)event: hermes.tool.progress\(newline)data: progress\(newline)\(newline)data: 你好🌕\(newline)data: second\(newline)\(newline)data: [DONE]\(newline)\(newline)"
            var parser = SSEByteParser()
            let events = Array(input.utf8).compactMap { parser.feed($0) }
            XCTAssertEqual(events.count, 3)
            XCTAssertEqual(events[0].event, "hermes.tool.progress")
            XCTAssertEqual(events[1].event, "message")
            XCTAssertEqual(events[1].data, "你好🌕\nsecond")
            XCTAssertEqual(events[2].data, "[DONE]")
        }
    }

    func testSSEIgnoresKeepaliveAndSeparatesToolEvents() throws {
        var parser = SSEParser()
        XCTAssertNil(parser.feed(": keepalive"))
        XCTAssertNil(parser.feed(""))
        XCTAssertNil(parser.feed("event: hermes.tool.progress"))
        XCTAssertNil(parser.feed("data: {\"tool\":\"search\"}"))
        let tool = parser.feed("")
        XCTAssertEqual(tool?.event, "hermes.tool.progress")
        XCTAssertEqual(tool?.data, "{\"tool\":\"search\"}")
        XCTAssertNil(parser.feed("data: [DONE]"))
        XCTAssertEqual(parser.feed("")?.data, "[DONE]")
    }
}
