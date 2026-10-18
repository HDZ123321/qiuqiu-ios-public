import Foundation

// Native adaptation of the reference app's prose / fenced-code presentation.
public struct MessageBlock: Identifiable {
    public let id: Int
    public let text: String
    public let language: String?
    public static func parse(_ source: String) -> [MessageBlock] {
        var result: [MessageBlock] = [], lines: [String] = []
        var fence: String?, language: String?
        func flush() {
            guard !lines.isEmpty else { return }
            result.append(MessageBlock(id: result.count, text: lines.joined(separator: "\n"), language: language))
            lines = []
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) && trimmed.dropFirst(marker.count).allSatisfy({ $0 == marker.first! }) {
                    flush(); fence = nil; language = nil
                } else { lines.append(line) }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); let marker = String(trimmed.prefix(3)); fence = marker
                language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else { lines.append(line) }
        }
        flush(); return result
    }
}
