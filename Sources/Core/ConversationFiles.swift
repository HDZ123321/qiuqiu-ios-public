import Foundation

/// Provenance is persisted on an actual assistant message, never inferred from a path/title.
public enum ConversationFiles {
    public struct Source: Equatable, Identifiable {
        public let chatID: UUID
        public let messageID: UUID
        public let runID: String
        public var id: String { runID }
    }
    public static func sources(in chat: Chat) -> [Source] {
        var seen = Set<String>()
        return chat.messages.compactMap { message in
            guard message.role == "assistant", let runID = message.artifactRunID,
                  runID.hasPrefix("run_"), runID.count <= 200,
                  runID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }),
                  seen.insert(runID).inserted else { return nil }
            return Source(chatID: chat.id, messageID: message.id, runID: runID)
        }
    }
}
