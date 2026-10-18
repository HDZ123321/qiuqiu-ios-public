import Foundation

// Frame raw bytes before decoding UTF-8. AsyncBytes.lines omits empty lines,
// which are semantically significant SSE event delimiters.
public struct SSEByteParser {
    private var line: [UInt8] = []
    private var previousCR = false
    private var parser = SSEParser()
    public init() {}
    public mutating func feed(_ byte: UInt8) -> SSEEvent? {
        if byte == 10 && previousCR { previousCR = false; return nil }
        previousCR = byte == 13
        if byte == 10 || byte == 13 {
            defer { line.removeAll(keepingCapacity: true) }
            return parser.feed(String(decoding: line, as: UTF8.self))
        }
        line.append(byte)
        return nil
    }
}
