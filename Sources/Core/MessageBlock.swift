import Foundation

public struct MessageReadPosition {
    public private(set) var following = true
    public private(set) var hasNewContent = false
    public init() {}
    public mutating func contentChanged() { if !following { hasNewContent = true } }
    public mutating func userScrolled(distanceFromBottom: Double) {
        following = distanceFromBottom < 100
        if following { hasNewContent = false }
    }
    public mutating func follow() { following = true; hasNewContent = false }
}

public enum ReplyLink {
    public static func external(_ source: String) -> URL? {
        guard let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

/// Presentation only. Callers retain the original message for whole-message copy.
public struct MessageBlock: Identifiable {
    public enum Kind: Equatable { case prose, heading, listItem, quote, table, code }
    public enum ColumnAlignment: Equatable { case leading, center, trailing }
    public let id: Int // Source line, stable as a streaming tail grows.
    public let text: String
    public let language: String?
    public var kind: Kind = .prose
    public var rows: [[String]] = []
    public var level: Int = 0
    public var marker: String = ""
    public var checked: Bool? = nil
    public var alignments: [ColumnAlignment] = []

    private static func match(_ pattern: String, _ line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: line).map { String(line[$0]) } ?? "" }
    }
    private static func heading(_ line: String) -> [String]? {
        guard var h = match("^ {0,3}(#{1,6})[ \\t]+(.+)$", line) else { return nil }
        h[2] = h[2].replacingOccurrences(of: "[ \\t]+#+[ \\t]*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return h
    }
    private static func item(_ line: String) -> [String]? { match("^([ \\t]*)([-+*]|[0-9]{1,9}[.)])[ \\t]+(.*)$", line) }
    private static func cells(_ source: String) -> [String] {
        let s = source.trimmingCharacters(in: .whitespaces)
        var result: [String] = [], cell = "", escaped = false, ticks = 0
        let chars = Array(s); var i = 0
        while i < chars.count {
            let c = chars[i]
            if escaped { cell.append(c); escaped = false; i += 1; continue }
            if c == "\\" { cell.append(c); escaped = true; i += 1; continue }
            if c == "`" {
                var end = i; while end < chars.count && chars[end] == "`" { end += 1 }
                let n = end - i
                if ticks == 0 { ticks = n } else if ticks == n { ticks = 0 }
                cell += String(repeating: "`", count: n); i = end; continue
            }
            if c == "|" && ticks == 0 { result.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else { cell.append(c) }
            i += 1
        }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("|") { result.removeFirst() }
        if result.last == "" && s.hasSuffix("|") && !s.hasSuffix("\\|") { result.removeLast() }
        return result
    }
    private static func tableAlignment(_ header: String, _ delimiter: String) -> [ColumnAlignment]? {
        let head = cells(header), parts = cells(delimiter)
        guard head.count >= 2, parts.count == head.count,
              parts.allSatisfy({ match("^:?-{3,}:?$", $0) != nil }) else { return nil }
        return parts.map { $0.hasSuffix(":") ? ($0.hasPrefix(":") ? .center : .trailing) : .leading }
    }
    public static func parse(_ source: String) -> [MessageBlock] {
        let lines = source.components(separatedBy: "\n")
        var result: [MessageBlock] = [], i = 0
        func block(_ start: Int, _ text: String, _ kind: Kind, _ language: String? = nil) -> MessageBlock {
            MessageBlock(id: start, text: text, language: language, kind: kind)
        }
        while i < lines.count {
            let start = i, line = lines[i], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(while: { $0 == trimmed.first! })), language = String(trimmed.drop(while: { $0 == trimmed.first! })).trimmingCharacters(in: .whitespaces)
                i += 1; var body: [String] = []
                while i < lines.count {
                    let close = lines[i].trimmingCharacters(in: .whitespaces)
                    if close.hasPrefix(marker) && close.dropFirst(marker.count).allSatisfy({ $0 == marker.first! }) { i += 1; break }
                    body.append(lines[i]); i += 1
                }
                result.append(block(start, body.joined(separator: "\n"), .code, language)); continue
            }
            if let h = heading(line) {
                var b = block(start, h[2], .heading); b.level = min(3, h[1].count)
                result.append(b); i += 1; continue
            }
            if let list = item(line) {
                let indent = list[1].replacingOccurrences(of: "\t", with: "    ").count
                var text = list[3], checked: Bool?
                if let task = match("^\\[([ xX])\\][ \\t]+(.*)$", text) { checked = task[1] != " "; text = task[2] }
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty, item(lines[i]) == nil, heading(lines[i]) == nil {
                    let nextIndent = lines[i].prefix(while: { $0 == " " || $0 == "\t" }).count
                    guard nextIndent > indent else { break }
                    text += "\n" + String(lines[i].dropFirst(min(nextIndent, indent + list[2].count + 1))); i += 1
                }
                var b = block(start, text, .listItem); b.level = indent / 2; b.marker = list[2]; b.checked = checked
                result.append(b); continue
            }
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    let body = t.dropFirst(); quote.append(String(body.first == " " ? body.dropFirst() : body)); i += 1
                }
                result.append(block(start, quote.joined(separator: "\n"), .quote)); continue
            }
            if i + 1 < lines.count, let alignment = tableAlignment(line, lines[i+1]) {
                var rows = [cells(line)]; i += 2
                while i < lines.count, lines[i].contains("|"), cells(lines[i]).count == alignment.count {
                    rows.append(cells(lines[i])); i += 1
                }
                var b = block(start, lines[start..<i].joined(separator: "\n"), .table)
                b.rows = rows; b.alignments = alignment; result.append(b); continue
            }
            var prose = [line]; i += 1
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || heading(lines[i]) != nil || item(lines[i]) != nil || t.hasPrefix(">") || t.hasPrefix("```") || t.hasPrefix("~~~") { break }
                if i + 1 < lines.count && tableAlignment(lines[i], lines[i+1]) != nil { break }
                prose.append(lines[i]); i += 1
            }
            result.append(block(start, prose.joined(separator: "\n"), .prose))
        }
        return result
    }
}
