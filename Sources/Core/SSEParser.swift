import Foundation

public struct SSEEvent: Equatable {
    public let event: String
    public let data: String
}

public struct SSEParser {
    private var event = "message"
    private var data: [String] = []
    public init() {}
    public mutating func feed(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { event = "message"; data = [] }
            guard !data.isEmpty else { return nil }
            return SSEEvent(event: event, data: data.joined(separator: "\n"))
        }
        guard !line.hasPrefix(":") else { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if field == "event" { event = value }
        if field == "data" { data.append(value) }
        return nil
    }
}
