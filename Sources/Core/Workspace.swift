import Foundation

public enum RecentPreview {
    public static func text(_ source: String) -> String {
        var text = source.replacingOccurrences(of: #"(?m)^\s*```[^\n]*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"!?\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}(#{1,6}\s+|>\s*)"#, with: "", options: .regularExpression)
        for delimiter in ["**", "__", "~~", "`", "*"] { text = text.replacingOccurrences(of: delimiter, with: "") }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    public static func date(_ value: Date) -> String {
        let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN")
        format.setLocalizedDateFormatFromTemplate("MMM d EEEE")
        return format.string(from: value)
    }
}

public enum WorkspacePath {
    public static func validate(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 1024 else { throw ClientError.message("文件路径无效。") }
        let parts=path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count<=12, parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && !$0.contains("\\") && !$0.contains("%") && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else { throw ClientError.message("文件路径不在允许范围内。") }
    }
}
public struct WorkspaceEntry: Decodable, Identifiable {
    public let name: String
    public let path: String
    public let directory: Bool
    public let size: Int
    public let modified: Double
    public var id: String { path }
}
public struct WorkspaceListing: Decodable {
    public let scope: String
    public let path: String
    public let max_bytes: Int
    public let entries: [WorkspaceEntry]
}
