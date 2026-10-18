import Foundation

public enum ReplyLink {
    public static func external(_ source: String) -> URL? {
        guard let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

// Native adaptation of the authorized reference's paragraph/quote/table/code blocks.
public struct MessageBlock: Identifiable {
    public enum Kind: Equatable { case prose, quote, table, code }
    public let id: Int
    public let text: String
    public let language: String?
    public var kind: Kind = .prose
    public var rows: [[String]] = []
    public static func parse(_ source: String) -> [MessageBlock] {
        var result: [MessageBlock] = [], lines: [String] = []
        var fence: String?, language: String?
        func append(_ text: String, _ kind: Kind, _ rows: [[String]] = []) {
            result.append(MessageBlock(id: result.count, text: text, language: kind == .code ? language ?? "" : nil, kind: kind, rows: rows))
        }
        func cells(_ line: String) -> [String] {
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("|") { s.removeFirst() }; if s.hasSuffix("|") { s.removeLast() }
            return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func flush() {
            guard !lines.isEmpty else { return }
            if fence != nil { append(lines.joined(separator: "\n"), .code) }
            else {
                var i = 0
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
                    if lines[i].hasPrefix(">") {
                        var quote: [String] = []
                        while i < lines.count && lines[i].hasPrefix(">") { quote.append(String(lines[i].dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1 }
                        append(quote.joined(separator: "\n"), .quote)
                    } else if i+1 < lines.count, lines[i].contains("|"), cells(lines[i+1]).allSatisfy({ cell in
                        let s = cell.replacingOccurrences(of: ":", with: ""); return s.count >= 3 && s.allSatisfy { $0 == "-" }
                    }) {
                        var rows = [cells(lines[i])]; i += 2
                        while i < lines.count && lines[i].contains("|") && !lines[i].isEmpty { rows.append(cells(lines[i])); i += 1 }
                        append(rows.map { $0.joined(separator: " | ") }.joined(separator: "\n"), .table, rows)
                    } else {
                        var prose = [lines[i]]; i += 1
                        while i < lines.count && !lines[i].isEmpty && !lines[i].hasPrefix(">") {
                            if i+1 < lines.count && lines[i].contains("|") && lines[i+1].contains("---") { break }
                            prose.append(lines[i]); i += 1
                        }
                        append(prose.joined(separator: "\n"), .prose)
                    }
                }
            }
            lines = []
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) && trimmed.dropFirst(marker.count).allSatisfy({ $0 == marker.first! }) {
                    flush(); fence = nil; language = nil
                } else { lines.append(line) }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); fence = String(trimmed.prefix(3)); language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else { lines.append(line) }
        }
        flush(); return result
    }
}
