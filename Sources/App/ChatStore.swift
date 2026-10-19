import SwiftUI
#if SWIFT_PACKAGE
import HermesCore
#endif

@MainActor final class ChatStore: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var selected: UUID?
    @Published var settings = ConnectionSettings()
    @Published var error: String?
    @Published var busy = false
    @Published var connected = false
    @Published var approvalBusy = false
    @Published var toolProgress = ""
    @Published var attachments: [ChatAttachment] = []
    @Published var attachmentLoading = false
    @Published var startedAt = Date()
    private var generation: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var epoch = UUID()
    var foreground = false
    private let api: HermesAPI
    private let saveChats: ([Chat]) throws -> Void
    private let sleep: (UInt64) async throws -> Void
    var current: Chat? { chats.first { $0.id == selected } }
    var activeChat: Chat? { chats.first { $0.run?.terminal == false } }
    var activeRun: PendingRun? { activeChat?.run ?? current?.run }
    private var failureStreak = 0
    static let maxAutoRetries = 4
    init(api: HermesAPI = HermesAPI(), initialChats: [Chat]? = nil,
         save: @escaping ([Chat]) throws -> Void = ChatDisk.save,
         sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.api = api; self.saveChats = save; self.sleep = sleep
        DiagnosticLog.shared.record(.app)
        do {
            if let initialChats { chats = initialChats }
            else { settings = try CredentialStore.load(); chats = try ChatDisk.load() }
        }
        catch { self.error = "无法载入本地数据。" }
        if chats.isEmpty { newChat() } else { selected = chats[0].id }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-files"),
           let url=ProcessInfo.processInfo.environment["QIU_FILE_BASE"],
           let key=ProcessInfo.processInfo.environment["QIU_FILE_KEY"] {
            settings.serverURL=url; settings.bearer=key
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-replies") {
            settings.serverURL = "https://fixture.invalid"; settings.bearer = "synthetic-fixture-only"
            var reply = ChatMessage(role: "assistant", content: "Generated reply\nMEDIA:/synthetic/workspace/generated.png\nMEDIA:/synthetic/workspace/generated.txt")
            reply.artifactRunID = "run_fixture"
            if ProcessInfo.processInfo.arguments.contains("--ui-formatting") {
                reply.content = "> A quoted explanation wraps at accessibility sizes.\n\n| Feature | Result |\n| --- | --- |\n| Table | Readable |\n\n[Example link](https://example.org)\n\n```swift\n" + String(repeating: "let longValue = \"horizontal scrolling preserves the whole line\"\n", count: 15) + "```\n\n" + String(repeating: "Long reply remains selectable and wraps with Dynamic Type. ", count: 50)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-typography") { reply.content = TypographyFixture.text; reply.artifactRunID = nil }
            if ProcessInfo.processInfo.arguments.contains("--ui-conversation-files") {
                if ProcessInfo.processInfo.arguments.contains("--ui-files-unavailable") { reply.artifactRunID = nil }
                else if ProcessInfo.processInfo.arguments.contains("--ui-files-empty") { reply.artifactRunID = "run_empty" }
                else if ProcessInfo.processInfo.arguments.contains("--ui-files-error") { reply.artifactRunID = "run_error" }
                else if ProcessInfo.processInfo.arguments.contains("--ui-files-long") { reply.artifactRunID = "run_long" }
                else { reply.artifactRunID = "run_files" }
                reply.content = "File source message · stable fixture provenance"
            }
            var chat = Chat(messages: [reply])
            if ProcessInfo.processInfo.arguments.contains("--ui-approval") {
                chat.run = try? PendingRun(input: "synthetic fixture", model: "fixture", sessionID: nil, history: [], replyID: reply.id)
                try? chat.run?.apply(Data(#"{"run_id":"run_fixture","status":"waiting_for_approval","approval":{"request_id":"request_fixture","command":"Synthetic operation only: create a sample report","choices":["once","deny"]}}"#.utf8))
                busy = true; connected = true
            }
            chats = [chat]; selected = chat.id; error = nil
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-sessions") {
            chats = [Chat()]; selected = chats[0].id; error = nil
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-history") {
            let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            try? FileManager.default.createDirectory(at:documents,withIntermediateDirectories:true)
            try? Data("Synthetic provider fixture only".utf8).write(to:documents.appendingPathComponent("picker-fixture.txt"))
            try? Data(repeating:65,count:4*1024*1024+1).write(to:documents.appendingPathComponent("oversized-fixture.txt"))
            try? Data().write(to:documents.appendingPathComponent("empty-fixture.txt"))
            try? Data("Unicode provider fixture only".utf8).write(to:documents.appendingPathComponent(String(repeating:"研究",count:40)+".txt"))
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-history") || ProcessInfo.processInfo.arguments.contains("--ui-busy") {
            var history = Chat(messages: [ChatMessage(role: "user", content: "验收历史"), ChatMessage(role: "assistant", content: "**验收回复**\n```swift\nlet value = 1\n```")])
            if ProcessInfo.processInfo.arguments.contains("--ui-busy") {
                history.run = try? PendingRun(input: "UI fixture only", model: "fixture", sessionID: nil, history: [], replyID: UUID())
            }
            chats = [history, Chat()]; selected = history.id; error = nil
        }
        #endif
        busy = chats.contains { $0.run?.terminal == false }
    }
    func sceneChanged(_ phase: ScenePhase) {
        DiagnosticLog.shared.record(phase == .active ? .foreground : (phase == .background ? .background : .inactiveScene))
        if phase == .active { resume() } else if phase == .background { detach() }
        // .inactive (app switcher, banners) keeps live tasks; durable state is already persisted.
    }
    var canNavigate: Bool { true }
    var canEditConnection: Bool { !busy }
    var canSend: Bool { !busy && (current?.serverSource == nil || syncState[current!.id] == "live") }
    func persist() {
        do { try saveChats(chats) } catch { self.error = "保存对话失败。" }
    }
    func openServerSession(_ item: ServerSessionItem, pages: [ServerSessionMessages]) throws {
        var saved = chats
        let id = try ServerSessionImport.open(item, scope: ServerSessionImport.scope(settings), chats: &saved, pages: pages)
        try saveChats(saved)
        chats = saved; selected = id
        // No resume(), send(), run mutation or stop-target change on import.
        if foreground { startSync(for: id) } // Ongoing-conversation sync while the chat stays open.
    }
    // MARK: - Ongoing-conversation sync (bounded, foreground, no inference scheduled)
    @Published var syncState: [UUID: String] = [:] // chatID -> "live" | "busy" | "stale" | "loading"
    private var syncTask: Task<Void, Never>?
    static let syncInterval: UInt64 = 5_000_000_000
    /// Foreground-only automatic refresh for an opened server session chat. Polls the
    /// sync endpoint + stored history, merges new persisted user/assistant rows by
    /// server message ID, and reflects server busy state. Never sends, never mutates a
    /// pending/active run, pauses in background or when the chat is closed.
    func startSync(for chatID: UUID) {
        stopSync()
        guard let chat = chats.first(where: { $0.id == chatID }), chat.sessionID != nil, chat.serverSource != nil else { return }
        let token = UUID(); syncEpoch = token
        syncState[chatID] = "loading"
        syncTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.foreground, self.syncEpoch == token {
                await self.syncOnce(chatID: chatID, token: token)
                do { try await Task.sleep(nanoseconds: Self.syncInterval) } catch { return }
            }
        }
    }
    func stopSync() {
        syncEpoch = UUID()
        syncTask?.cancel(); syncTask = nil
    }
    private var syncEpoch = UUID()
    func syncOnce(chatID: UUID, token: UUID? = nil) async {
        let myToken = token ?? syncEpoch
        guard let i = chats.firstIndex(where: { $0.id == chatID }), let sessionID = chats[i].sessionID else { return }
        // Never sync-mutate a chat with a local pending/active run: keep task/stop identity intact.
        guard chats[i].run == nil || chats[i].run?.terminal == true else { syncState[chatID] = "stale"; return }
        syncState[chatID] = "loading"
        let configuration = settings
        do {
            let status = try await api.sessionSync(configuration, id: sessionID)
            guard chats.contains(where: { $0.id == chatID }), !Task.isCancelled, syncEpoch == myToken, ServerSessionImport.scope(configuration) == ServerSessionImport.scope(settings) else { return }
            do {
                // User rows can appear while busy; assistant rows appear on finalization.
                let pages = try await api.sessionTranscript(configuration, id: sessionID, profile: true)
                guard let k = chats.firstIndex(where: { $0.id == chatID }), !Task.isCancelled, syncEpoch == myToken, ServerSessionImport.scope(configuration) == ServerSessionImport.scope(settings), chats[k].run?.terminal != false else { return }
                if pages.allSatisfy({ $0.session_id == sessionID && $0.history == "stored_text" }) {
                    var updated = chats[k]
                    let before = updated.messages.count
                    // A completed app turn has local display placeholders, not native
                    // row IDs. Replace only that exact paired tail with canonical rows.
                    if updated.serverSource != nil, let run = updated.run, run.status == "completed",
                       let reply = updated.messages.firstIndex(where: { $0.id == run.replyID }),
                       reply == updated.messages.count - 1, reply > 0,
                       updated.messages[reply].serverMessageID == nil,
                       updated.messages[reply-1].role == "user", updated.messages[reply-1].serverMessageID == nil,
                       let final = pages.flatMap(\.items).last, final.role == "assistant", final.content == updated.messages[reply].content,
                       pages.flatMap(\.items).dropLast().last?.content == updated.messages[reply-1].content {
                        updated.messages.removeLast(2)
                    }
                    for page in pages { ServerSessionSyncEngine.merge(page, into: &updated) }
                    if updated.messages.count != before || updated.messages.map(\.serverMessageID) != chats[k].messages.map(\.serverMessageID) { chats[k] = updated; persist() }
                } else { throw ClientError.message("历史不可用") }
                syncState[chatID] = status.busyOnServer ? "busy" : status.can_continue ? "live" : "stale"
            }
        } catch {
            guard !Task.isCancelled, syncEpoch == myToken else { return }
            syncState[chatID] = "stale" // Honest: last check failed; not "live".
        }
    }
    func newChat() {
        guard !busy else { return }
        let chat = Chat(); chats.insert(chat, at: 0); selected = chat.id; toolProgress = ""; persist()
    }
    func delete(_ id: UUID) {
        guard !busy else { return }
        chats.removeAll { $0.id == id }
        if selected == id { selected = chats.first?.id }
        if chats.isEmpty { newChat() } else { persist() }
    }
    func conversations(query: String = "", archived: Bool = false) -> [Chat] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return chats.enumerated().filter { _, chat in
            (chat.archived == true) == archived && (needle.isEmpty || chat.title.localizedCaseInsensitiveContains(needle) || chat.messages.contains { $0.content.localizedCaseInsensitiveContains(needle) })
        }.sorted { a, b in
            if (a.element.pinned == true) != (b.element.pinned == true) { return a.element.pinned == true }
            return a.offset < b.offset
        }.map(\.element)
    }
    private func edit(_ id: UUID, change: (inout Chat) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        var saved = chats; change(&saved[i])
        do { try saveChats(saved); chats = saved } catch { self.error = "保存对话修改失败。" }
    }
    func rename(_ id: UUID, title: String) {
        edit(id) { $0.customTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
    }
    func togglePin(_ id: UUID) { edit(id) { $0.pinned = !($0.pinned == true) } }
    func toggleArchive(_ id: UUID) {
        guard chats.first(where: { $0.id == id })?.run?.terminal != false else { return }
        edit(id) { $0.archived = !($0.archived == true) }
    }
    func saveSettings(_ value: ConnectionSettings) throws {
        guard !busy else { throw ClientError.message("任务尚未结束，不能更换服务器。") }
        _ = try ServerEndpoint(value.serverURL)
        guard !value.bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !value.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.message("令牌和模型不能为空。") }
        try CredentialStore.save(value); settings = value
    }
    // Archival is append-only and never touches the active run or stop target.
    private func archiveTerminalRun(_ chat: Chat) {
        guard let run = chat.run, run.terminal else { return }
        let entry = RunHistoryStore.Entry(chatID: chat.id, chatTitle: chat.title, run: run)
        do { try RunHistoryStore().append(entry) } catch { /* History must never interrupt chatting. */ }
    }
    func check(_ value: ConnectionSettings) async throws -> [String] { try await api.models(value) }
    func detach() {
        DiagnosticLog.shared.record(.detach, id: activeRun?.replyID)
        foreground = false; epoch = UUID()
        generation?.cancel(); generation = nil; eventTask?.cancel(); eventTask = nil
        stopSync() // Bounded sync pauses in background/closed; resumes on foreground.
        connected = false; persist() // Never stops the server.
    }
    private func reconcile(_ data: Data, chatID: UUID) throws {
        guard let i = chats.firstIndex(where: { $0.id == chatID }), var run = chats[i].run else { return }
        let previous = run.status
        try run.apply(data); chats[i].run = run
        if run.runID != nil { attachments = [] } // Clear only after admission is confirmed; retries retain exact durable bytes.
        if previous != run.status { DiagnosticLog.shared.record(.runState, id: run.replyID, texts: run.output?.count, milliseconds: Int(Date().timeIntervalSince(run.createdAt) * 1000), state: DiagnosticLog.State(rawValue: run.status) ?? .unknown) }
        if let session = run.sessionID, chats[i].serverSource == nil { chats[i].sessionID = session }
        if let j = chats[i].messages.firstIndex(where: { $0.id == run.replyID }) {
            if let output = run.output { chats[i].messages[j].content = output }
            if run.status == "completed" { chats[i].messages[j].artifactRunID = run.runID }
            chats[i].messages[j].interrupted = run.terminal && run.status != "completed"
        }
        if run.status == "waiting_for_approval" && previous != run.status { DiagnosticLog.shared.record(.approvalSeen, id: run.replyID) }
        if run.terminal && previous != run.status { archiveTerminalRun(chats[i]) }
        busy = !run.terminal; try saveChats(chats)
    }
    func resume() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-replies") { return }
        if ProcessInfo.processInfo.arguments.contains("--ui-busy") { return } // No network or credentials in UI fixtures.
        #endif
        foreground = true
        // Restart bounded sync for the currently selected server session (foreground only).
        if let chat = current, chat.sessionID != nil, chat.run?.terminal != false { startSync(for: chat.id) }
        guard generation == nil else { return }
        guard let chat = chats.first(where: { $0.run?.terminal == false }), let run = chat.run else { busy = false; return }
        DiagnosticLog.shared.record(.resume, id: run.replyID, state: DiagnosticLog.State(rawValue: run.status) ?? .unknown)
        busy = true; startedAt = run.createdAt
        let token = UUID(); epoch = token
        let configuration = settings
        generation = Task {
            defer { if epoch == token { generation = nil; connected = false; eventTask?.cancel(); eventTask = nil; if foreground, let current, current.run?.terminal != false { startSync(for: current.id) } } }
            while !Task.isCancelled && foreground && epoch == token {
                do {
                    guard let i = chats.firstIndex(where: { $0.id == chat.id }), var pending = chats[i].run, !pending.terminal else { break }
                    if pending.runID == nil {
                        let capabilityData = try await api.runRequest(configuration, path: "capabilities", correlation: pending.replyID)
                        struct Capabilities: Decodable {
                            struct Features: Decodable {
                                struct Idempotency: Decodable { let supported: Bool; let durable: Bool; let retention_seconds: Int }
                                let run_submission: Bool; let run_status: Bool; let run_stop: Bool; let run_approval_response: Bool
                                let runs_idempotency: Idempotency
                            }
                            let features: Features
                        }
                        try Task.checkCancellation(); guard epoch == token else { return }
                        let features = try JSONDecoder().decode(Capabilities.self, from: capabilityData).features
                        guard features.run_submission && features.run_status && features.run_stop && features.run_approval_response && features.runs_idempotency.supported && features.runs_idempotency.durable && features.runs_idempotency.retention_seconds >= 86400 else { throw ClientError.message("服务器不具备所需持久任务能力。") }
                        guard Date().timeIntervalSince(pending.createdAt) < 23 * 3600 else { error = "创建结果不明且接近幂等保留期限；为避免重复执行，已停止自动提交。请人工核实服务器。"; break }
                        guard let latest = chats[i].run, latest.key == pending.key, !latest.terminal else { return }
                        pending = latest
                        // Persist BEFORE dispatch: a lost response must remain ambiguous.
                        var saved = chats; saved[i].run?.admissionDispatched = true
                        try saveChats(saved); chats = saved
                        let created = try await api.runRequest(configuration, path: "runs", method: "POST", body: pending.body, key: pending.key, correlation: pending.replyID)
                        try Task.checkCancellation(); guard epoch == token else { return }
                        try reconcile(created, chatID: chat.id); pending = chats[i].run!
                    }
                    guard let runID = pending.runID else { break }
                    let snapshot = try await api.runRequest(configuration, path: "runs/\(runID)", correlation: run.replyID)
                    try Task.checkCancellation(); guard epoch == token else { return }
                    try reconcile(snapshot, chatID: chat.id); connected = true; error = nil
                    guard chats[i].run?.terminal == false else { eventTask?.cancel(); break }
                    if chats[i].run?.stopRequested == true {
                        DiagnosticLog.shared.record(.stopSent, id: pending.replyID)
                        let stopped = try await api.runRequest(configuration, path: "runs/\(runID)/stop", method: "POST", body: Data("{}".utf8), correlation: pending.replyID)
                        try Task.checkCancellation(); guard epoch == token else { return }
                        try reconcile(stopped, chatID: chat.id)
                        chats[i].run?.stopRequested = false; try saveChats(chats)
                    }
                    if eventTask == nil {
                        eventTask = Task {
                            defer { if epoch == token { eventTask = nil } }
                            do { try await api.runEvents(configuration, runID: runID, correlation: pending.replyID) { [weak self] event in
                                guard let self, self.epoch == token else { return }; self.progress(event)
                            } } catch { DiagnosticLog.shared.record(.pollFallback, id: pending.replyID, code: (error as NSError).code) }
                        }
                    }
                } catch {
                    if Task.isCancelled || epoch != token { return }
                    DiagnosticLog.shared.record(.pollFallback, id: run.replyID, code: (error as NSError).code)
                    connected = false
                    if let failure = error as? HTTPFailure, failure.status == 409 {
                        self.error = "原会话正在处理或请求存在冲突；未创建新副本。保留同一提交编号，请稍后手动重连。"
                        break // Never create another intent or spin on a native busy response.
                    }
                    if failureStreak >= Self.maxAutoRetries {
                        DiagnosticLog.shared.record(.retryPaused, id: run.replyID, code: (error as NSError).code, state: DiagnosticLog.State(rawValue: run.status) ?? .unknown)
                        self.error = "连续 \(failureStreak) 次未核实服务器（最后代码 \((error as NSError).code)）。已暂停自动重试；任务保留在服务器，请稍后手动重连。"
                        break
                    }
                    let delay = UInt64(1 << failureStreak) * 2_000_000_000
                    DiagnosticLog.shared.record(.retryScheduled, id: run.replyID, milliseconds: Int(delay / 1_000_000))
                    self.error = "连接待核实，服务器任务未被本机停止；保留任务编号并自动重连（代码 \((error as NSError).code)）。"
                    failureStreak += 1
                    do { try await sleep(delay) } catch { return }
                    continue
                }
                failureStreak = 0
                do { try await sleep(2_000_000_000) } catch { return }
            }
        }
    }
    private func progress(_ event: SSEEvent) {
        guard let data = event.data.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let name = object["event"] as? String ?? event.event
        let tool = String((object["tool"] as? String ?? "工具").prefix(80))
        switch name {
        case "tool.started": DiagnosticLog.shared.record(.toolStarted, id: activeRun?.replyID); toolProgress = "开始：\(tool)"
        case "tool.completed": DiagnosticLog.shared.record(.toolCompleted, id: activeRun?.replyID); toolProgress = "\((object["error"] as? Bool == true) ? "失败/拒绝" : "完成")：\(tool)"
        case "subagent.start": toolProgress = "子任务执行中"
        case "subagent.complete": toolProgress = "子任务已返回"
        case "message.interim": toolProgress = String((object["text"] as? String ?? "").prefix(800))
        case "approval.request": DiagnosticLog.shared.record(.approvalSeen, id: activeRun?.replyID); toolProgress = "等待批准，请阅读服务器请求。"
        default: break // Final output only comes from authoritative polling, never concatenated.
        }
    }
    func cancel() {
        guard let i = chats.firstIndex(where: { $0.run?.terminal == false }) else { return }
        DiagnosticLog.shared.record(.stopIntent, id: chats[i].run?.replyID)
        if chats[i].run?.definitelyUnsent == true {
            var saved = chats
            saved[i].run?.status = "cancelled"
            do {
                try saveChats(saved)
                detach(); chats = saved; busy = false; error = nil
                DiagnosticLog.shared.record(.abandonedUnsent, id: saved[i].run?.replyID)
            } catch { self.error = "放弃未保存，请重试。" }
            return
        }
        chats[i].run?.stopRequested = true
        do { try saveChats(chats); resume() } catch { self.error = "停止请求未保存，请重试。" }
    }
    func approve(_ choice: String, expectedKey: String? = nil, expectedRequestID: String? = nil) {
        guard !approvalBusy, connected, ["once", "deny"].contains(choice), let run = activeRun,
              expectedKey == nil || expectedKey == run.key,
              run.status == "waiting_for_approval", let approval = run.approval,
              approval.choices?.contains(choice) == true, let requestID = approval.request_id,
              expectedRequestID == nil || expectedRequestID == requestID,
              let runID = run.runID, let chatID = activeChat?.id else { return }
        let configuration = settings
        let connectionEpoch = epoch
        DiagnosticLog.shared.record(choice == "once" ? .approvalOnce : .approvalDeny, id: run.replyID)
        approvalBusy = true
        Task {
            defer { approvalBusy = false }
            do {
                let body = try JSONSerialization.data(withJSONObject: ["choice": choice, "request_id": requestID])
                _ = try await api.runRequest(configuration, path: "runs/\(runID)/approval", method: "POST", body: body)
                let snapshot = try await api.runRequest(configuration, path: "runs/\(runID)", correlation: run.replyID)
                guard epoch == connectionEpoch, activeRun?.key == run.key else { return }
                try reconcile(snapshot, chatID: chatID)
            } catch { self.error = "批准结果未确认；不会自动重发，请核实服务器状态。" }
        }
    }
    func addAttachment(_ attachment: ChatAttachment) throws {
        guard !busy else { throw AttachmentFailure(.busy) }
        try AttachmentFailure.validateMessage(count: attachments.count+1, bytes: attachments.reduce(attachment.data.count, { $0 + $1.data.count }))
        attachments.append(attachment)
        DiagnosticLog.shared.record(.attachmentAdded,frames:attachments.count,texts:attachment.data.count)
    }
    func send(_ text: String) {
        guard !busy, let id = selected, let i = chats.firstIndex(where: { $0.id == id }) else { return }
        if let source = chats[i].serverSource {
            guard source.scope == ServerSessionImport.scope(settings) else { error = "此服务器会话属于另一连接，请恢复原连接后继续。"; return }
            guard canSend else { error = "原会话忙碌或同步状态待核实，暂不能发送。"; return }
        }
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachmentLoading, !typed.isEmpty || !attachments.isEmpty else { return }
        let content = typed.isEmpty ? "请阅读这些附件。" : typed
        do {
            _ = try ServerEndpoint(settings.serverURL)
            guard !settings.bearer.isEmpty else { throw ClientError.message("请先保存连接设置。") }
            if let source = chats[i].serverSource, source.scope != ServerSessionImport.scope(settings) {
                throw ClientError.message("此服务器会话属于另一连接，请恢复原连接后继续。")
            }
            let reply = ChatMessage(role: "assistant", content: "")
            let pending = try PendingRun(input: content, model: settings.model, sessionID: chats[i].sessionID, history: chats[i].messages, replyID: reply.id, attachments: attachments)
            var saved = chats
            var user = ChatMessage(role: "user", content: content)
            user.attachmentNames = attachments.isEmpty ? nil : attachments.map(\.name)
            saved[i].messages.append(user); saved[i].messages.append(reply); saved[i].run = pending
            try saveChats(saved) // Do not send without a durable intent.
            DiagnosticLog.shared.record(.send, id: pending.replyID)
            stopSync() // Local run owns this chat now; sync must not fight the active task.
            chats = saved; busy = true; toolProgress = ""; error = nil; resume()
        } catch { self.error = "无法开始任务：\(error.localizedDescription)" }
    }
}
