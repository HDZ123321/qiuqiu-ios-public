import Foundation

// Persistently retained, client-captured execution history for runs THIS app
// created. This is local history of actual captured client runs only — clearly
// labeled in the UI as NOT the full server history. Never mutates the active
// run or stop target; no task creation/execution lives here.
public struct RunHistoryStore {
    public struct Source: RawRepresentable, Codable, Equatable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let local = Source(rawValue: "local")
        public static let serverPage = Source(rawValue: "server_page")
    }
    public struct Entry: Codable, Identifiable, Equatable {
        public var id: UUID { run.replyID }
        public var chatID: UUID
        public var chatTitle: String
        public var run: PendingRun
        public var capturedAt: Date
        public var source: Source
        public init(chatID: UUID, chatTitle: String, run: PendingRun, capturedAt: Date = Date(), source: Source = .local) {
            self.chatID = chatID; self.chatTitle = chatTitle; self.run = run
            self.capturedAt = capturedAt; self.source = source
        }
        public static func sourceLabel(_ source: Source) -> String {
            source == .local ? "本机记录" : "服务器登记"
        }
    }
    public struct ServerPage: Decodable {
        public struct Item: Decodable, Identifiable {
            public let run_id: String
            public let session: String?
            public let created_seq: Int
            public var id: String { run_id }
        }
        public let items: [Item]
        public let next_cursor: Int?
    }
    let directory: URL
    let limit: Int
    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RunHistory"), limit: Int = 200) {
        self.directory = directory
        self.limit = max(1, limit)
    }
    var entries: [Entry] { (try? load()) ?? [] }
    public func load() throws -> [Entry] {
        let url = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
    }
    // Only terminal runs are ever archived; an active run stays the exclusive
    // stop/resume target of the chat that owns it.
    public func append(_ entry: Entry) throws {
        guard entry.run.terminal else { throw ClientError.message("仅保留已结束的任务记录；进行中的任务不会进入历史。") }
        var all = try load()
        // Newest wins for the same reply: a retried terminal state supersedes.
        all.removeAll { $0.run.replyID == entry.run.replyID }
        all.insert(entry, at: 0)
        if all.count > limit { all = Array(all.prefix(limit)) }
        try write(all)
    }
    public func clear() throws { try write([]) }
    private func write(_ all: [Entry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        #if os(iOS)
        try JSONEncoder().encode(all).write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try JSONEncoder().encode(all).write(to: url, options: [.atomic])
        #endif
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
    // Backward-compatible migration from per-chat latest runs: copy terminal
    // runs into history WITHOUT removing the per-chat field, so older app
    // versions can still read chats.json unchanged.
    public static func migrationEntries(chats: [Chat], capturedAt: Date = Date()) -> [Entry] {
        chats.compactMap { chat in
            guard let run = chat.run, run.terminal else { return nil }
            return Entry(chatID: chat.id, chatTitle: chat.title, run: run, capturedAt: capturedAt)
        }
    }
    // Filter helpers matching the reference list (state/time/search).
    public static func filter(_ entries: [Entry], query: String, status: String?, before: Date?) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if let status, !status.isEmpty, entry.run.status != status { return false }
            if let before, entry.capturedAt >= before { return false }
            if !needle.isEmpty {
                let haystack = [entry.chatTitle, entry.run.label, entry.run.output ?? ""]
                if !haystack.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) { return false }
            }
            return true
        }
    }
}
