import Foundation

/// Provenance is persisted on an actual assistant message, never inferred from a path/title.
public enum ConversationFiles {
    public struct Source: Equatable, Identifiable {
        public let chatID: UUID
        public let messageID: UUID
        public let runID: String
        public var id: String { runID }
    }
    public struct Entry: Identifiable {
        public let artifact: ReplyArtifact
        public let source: Source
        // Opaque artifact identity is workspace-scoped; repeated references show once.
        public var id: String { artifact.id }
    }
    public struct Index {
        public private(set) var items: [Entry] = []
        public init() {}
        public mutating func append(_ artifacts: [ReplyArtifact], from source: Source) {
            var seen = Set(items.map(\.id))
            for artifact in artifacts where seen.insert(artifact.id).inserted {
                items.append(Entry(artifact: artifact, source: source))
            }
        }
    }
    public static func canJump(_ source: Source, in chats: [Chat]) -> Bool {
        chats.contains { chat in
            chat.id == source.chatID && chat.messages.contains { $0.id == source.messageID && $0.role == "assistant" && $0.artifactRunID == source.runID }
        }
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
