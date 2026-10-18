import Foundation
import CryptoKit

public struct ServerSessionItem: Decodable, Identifiable {
    public let session_id: String
    public let created_seq: Int
    public let run_count: Int
    public let history: String
    public let title: String?
    public let title_source: String?
    public var displayTitle: String { title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : "未命名会话" }
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
        let complete = !pages.isEmpty && pages.allSatisfy({ $0.history == "stored_text" }) && pages.last?.next_offset == nil
        let existing = chats.firstIndex(where: { $0.sessionID == item.session_id && ($0.serverSource?.scope == scope || $0.serverSource == nil) })
        var chat = existing.map { chats[$0] } ?? Chat()
        chat.sessionID = item.session_id
        if existing == nil { chat.customTitle = item.title }
        // Never replace local messages, rename, archive, or active task. Imported
        // server IDs provide exact dedupe; legacy/native local chats have no safe
        // message mapping, so retain them intact instead of duplicating history.
        let canMerge = existing == nil || (chat.serverSource?.scope == scope && (chat.messages.isEmpty || chat.messages.allSatisfy { $0.serverMessageID != nil }))
        var seen = Set(chat.messages.compactMap(\.serverMessageID))
        if complete && canMerge {
            for message in pages.flatMap(\.items) where ["user", "assistant"].contains(message.role) && seen.insert(message.id).inserted {
                var local = ChatMessage(role: message.role, content: message.content)
                local.serverMessageID = message.id
                chat.messages.append(local)
            }
        }
        if existing == nil || canMerge {
            let history = complete ? "stored_text" : pages.contains(where: { $0.history == "unavailable" }) ? "unavailable" : "not_fetched"
            chat.serverSource = ServerSessionSource(scope: scope, history: history)
        }
        if let existing { chats[existing] = chat } else { chats.append(chat) }
        return chat.id
    }
}
