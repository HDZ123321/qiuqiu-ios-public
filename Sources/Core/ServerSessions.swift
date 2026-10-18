import Foundation
import CryptoKit

public struct ServerSessionItem: Decodable, Identifiable {
    public let session_id: String
    public let created_seq: Int
    public let run_count: Int
    public let history: String
    public var id: String { session_id }
}
public struct ServerSessionPage: Decodable {
    public let items: [ServerSessionItem]
    public let next_cursor: Int?
}
public struct ServerSessionMessages: Decodable {
    public struct Item: Decodable { public let id: String; public let role: String; public let content: String }
    public let session_id: String
    public let history: String
    public let items: [Item]
    public let next_offset: Int?
}
public struct ServerSessionSource: Codable {
    public var scope: String
    public var history: String
}
public enum ServerSessionImport {
    // Local identity only: never logged or sent. No raw credential in chats.json.
    public static func scope(_ settings: ConnectionSettings) -> String {
        let endpoint = (try? ServerEndpoint(settings.serverURL).url(for: "app/sessions").absoluteString) ?? settings.serverURL
        return SHA256.hash(data: Data((endpoint + "\u{0}" + settings.bearer).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    @discardableResult public static func open(_ item: ServerSessionItem, scope: String, chats: inout [Chat], pages: [ServerSessionMessages] = []) throws -> UUID {
        guard !item.session_id.isEmpty, item.session_id.count <= 200,
              item.session_id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
              pages.allSatisfy({ $0.session_id == item.session_id }) else { throw ClientError.message("会话身份不匹配。") }
        // Existing local data always wins, including renamed/archived/edited chats.
        // Untagged legacy matches are deliberately reused, never overwritten.
        if let existing = chats.first(where: { $0.sessionID == item.session_id && ($0.serverSource?.scope == scope || $0.serverSource == nil) }) { return existing.id }
        var chat = Chat()
        chat.sessionID = item.session_id
        chat.customTitle = "服务器会话 · \(item.created_seq)"
        var seen = Set<String>()
        let complete = !pages.isEmpty && pages.allSatisfy({ $0.history == "stored_text" }) && pages.last?.next_offset == nil
        for page in complete ? pages : [] {
            for message in page.items where ["user", "assistant"].contains(message.role) && seen.insert(message.id).inserted {
                chat.messages.append(ChatMessage(role: message.role, content: message.content))
            }
        }
        let history = complete ? "stored_text" : pages.contains(where: { $0.history == "unavailable" }) ? "unavailable" : "not_fetched"
        chat.serverSource = ServerSessionSource(scope: scope, history: history)
        // Append: an in-flight polling iteration may retain an existing chat index.
        chats.append(chat)
        return chat.id
    }
}
