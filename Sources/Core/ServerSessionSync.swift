import Foundation

/// Server-side sync snapshot for one app-owned session. Honest state only:
/// `channel_active` means the native per-session turn lease is held (any channel,
/// e.g. WeChat mid-turn) — the App must show busy/wait, never send a conflicting turn.
/// `serverState` is the latest run state known to the boundary; `unknown` renders as
/// stale/unchecked, never as "live".
public struct ServerSessionSync: Decodable, Equatable {
    public let session_id: String
    public let channel_active: Bool
    public let server_state: String
    public let last_checked: Int
    public let can_continue: Bool
    public let title: String?
    public var busyOnServer: Bool { channel_active }
}

public enum ServerSessionSyncEngine {
    /// Merge a stored-history page into an imported chat. Appends only messages not
    /// already present (by serverMessageID), never overwrites local edits, never touches
    /// a local pending/active run, and keeps one chat per server session ID.
    public static func merge(_ page: ServerSessionMessages, into chat: inout Chat) {
        guard page.history == "stored_text", chat.run?.terminal != false else { return }
        if let run = chat.run, run.status == "completed",
           let index = chat.messages.firstIndex(where: { $0.id == run.replyID }), index == chat.messages.count - 1, index > 0,
           chat.messages[index-1].quote != nil,
           chat.messages[index].serverMessageID == nil, chat.messages[index-1].serverMessageID == nil,
           page.items.count >= 2 {
            let tail = Array(page.items.suffix(2))
            if tail[0].role == "user", tail[1].role == "assistant",
               tail[0].content == chat.messages[index-1].wireContent, tail[1].content == chat.messages[index].content {
                chat.messages[index-1].serverMessageID = tail[0].id
                chat.messages[index].serverMessageID = tail[1].id
            }
        }
        var seen = Set(chat.messages.compactMap(\.serverMessageID))
        for message in page.items where ["user", "assistant"].contains(message.role) {
            guard seen.insert(message.id).inserted else { continue }
            var local = ChatMessage(role: message.role, content: message.content)
            local.serverMessageID = message.id
            chat.messages.append(local)
        }
    }
}
