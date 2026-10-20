#if os(iOS)
import SwiftUI
import UIKit

// iOS adaptation of Hermes Android 3.8.8 simple home, sessions and execution center.
struct CompanionView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var chatOpen = false
    @AppStorage("qiu.skin") private var skin = "glass"
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { skin == "warm" ? Color(red: 0.247, green: 0.420, blue: 0.341) : skin == "quiet" ? Color.primary : Color(red: 0.153, green: 0.373, blue: 0.659) }
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { home }.tabItem { Label("助理", systemImage: "sparkles") }.tag(0)
            NavigationStack { ConversationsView { chatOpen = true } }.tabItem { Label("回看", systemImage: "bubble.left.and.bubble.right") }.tag(1)
            NavigationStack { TasksView { chatOpen = true } }.tabItem { Label("任务", systemImage: "checklist") }.tag(2)
            NavigationStack { WorkspaceView() }.tabItem { Label("文件", systemImage: "folder") }.tag(4)
            NavigationStack {
                List {
                    Section { Label("球球", systemImage: "sparkles").font(.title2.bold()); Text("自己的助理，随时接着聊").foregroundStyle(.secondary) }
                    Section("连接与诊断") { NavigationLink("连接设置 · 诊断日志") { SettingsView(store: store) } }
                    Section("外观") { Picker("主题", selection: $skin) { Text("液态玻璃").tag("glass"); Text("温暖灵动").tag("warm"); Text("安静耐看").tag("quiet") } }
                    Section("关于") {
                        Text("球球 iOS · Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知")")
                        Text("界面适配自 Hermes Android 3.8.8。原作 jeromeleeqy-hash；用户报告已获作者原作使用许可。保留来源，未使用第三方图标或字体。") .font(.footnote)
                        Link("原项目与来源", destination: URL(string: "https://github.com/jeromeleeqy-hash/Hermes-Android")!)
                        Text("本版文件仅限专用安全工作区；定时安排使用独立受限接口，未开放时不可用。不含完整语音会话/朗读及深度助理整理。聊天麦克风仅设备端转文字草稿，需手动发送。跟我说打开聊天。人物为原作静态资源；玻璃材质使用 iOS 原生适配。") .font(.footnote).foregroundStyle(.secondary)
                    }
                }.navigationTitle("我的")
            }.tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(3)
        }
        .tint(accent)
        .sheet(isPresented: $chatOpen) { NavigationStack { ConversationDetail() } }
        .onAppear { store.resume() }
        .onChange(of: phase) { store.sceneChanged($0) }
    }
    private var home: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Text(RecentPreview.date(Date())).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button { tab = 1 } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44).background(.thinMaterial, in: Circle()) }.accessibilityLabel("搜索对话")
                    Button { tab = 3 } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }.accessibilityLabel("设置")
                }
                VStack(spacing: 10) {
                    Text("你好，朋友").font(.title.bold())
                    Text(store.busy ? "有一件事正在进行，我在这里。" : "生活偶尔卡顿，也能继续").font(.subheadline).foregroundStyle(.secondary)
                    if let path = Bundle.main.path(forResource: "assistant", ofType: "png"), let image = UIImage(contentsOfFile: path) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 200).frame(height: skin == "quiet" ? 150 : 220).accessibilityLabel("球球人物")
                    }
                    Button {
                        if let active = store.activeChat { store.selected = active.id }
                        else if store.current?.archived == true { store.newChat() }
                        chatOpen = true
                    } label: {
                        Label("跟我说", systemImage: "text.bubble").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    Text("文字聊天").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                if store.busy { RunCard() }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("接着上次的事").font(.headline); Spacer(); Button("全部 ›") { tab = 1 } }
                    ForEach(Array(store.conversations().filter { !$0.messages.isEmpty }.prefix(2))) { chat in
                        Button { store.selected = chat.id; chatOpen = true } label: { ConversationRow(chat: chat) }.buttonStyle(.plain)
                        Divider()
                    }
                    Button { tab = 2 } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").frame(width: 38, height: 38).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) { Text("任务与执行").font(.headline); Text("查看进度、授权和执行记录").font(.subheadline).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }.padding(.vertical, 12)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 14)
            }.padding(22)
        }.background(scheme == .dark ? Color(.systemBackground) : skin == "quiet" ? Color(red: 0.98, green: 0.977, blue: 0.96) : Color(.systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ConversationRow: View {
    let chat: Chat
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chat.pinned == true ? "pin.fill" : "bubble.left").foregroundStyle(.tint).frame(width: 38, height: 38).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(chat.title).font(.headline).lineLimit(2)
                Text(chat.run?.terminal == false ? chat.run!.label : chat.messages.last?.content.isEmpty == false ? RecentPreview.text(chat.messages.last!.content) : "还没有消息") .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
}

struct ConversationsView: View {
    @EnvironmentObject private var store: ChatStore
    let open: () -> Void
    @State private var query = ""
    @State private var archived = false
    @State private var renameID: UUID?
    @State private var name = ""
    @State private var deleteID: UUID?
    var body: some View {
        List {
            NavigationLink { ServerSessionsView(open: open) } label: {
                Label("服务器会话", systemImage: "externaldrive.badge.icloud")
            }.accessibilityIdentifier("server-sessions-navigation")
            Picker("范围", selection: $archived) { Text("最近").tag(false); Text("已归档").tag(true) }.pickerStyle(.segmented)
            if store.conversations(query: query, archived: archived).isEmpty { Text("没有匹配的对话").foregroundStyle(.secondary) }
            ForEach(store.conversations(query: query, archived: archived)) { chat in
                Button { store.selected = chat.id; open() } label: { ConversationRow(chat: chat) }.buttonStyle(.plain)
                    .contextMenu {
                        Button("重命名") { name = chat.title; renameID = chat.id }
                        Button(chat.pinned == true ? "取消置顶" : "置顶") { store.togglePin(chat.id) }
                        Button(archived ? "恢复" : "归档") { store.toggleArchive(chat.id) }.disabled(chat.run?.terminal == false)
                        Button("删除", role: .destructive) { deleteID = chat.id }.disabled(store.busy)
                    }
            }
        }.listStyle(.plain).searchable(text: $query, prompt: "搜索标题和消息")
        .navigationTitle("回看")
        .toolbar { Button { store.newChat(); open() } label: { Image(systemName: "square.and.pencil") }.disabled(!store.canSend).accessibilityLabel("新对话") }
        .alert("重命名", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("对话名称", text: $name)
            Button("保存") { if let id = renameID { store.rename(id, title: name) }; renameID = nil }
            Button("取消", role: .cancel) { renameID = nil }
        } message: { Text("留空恢复自动标题；不修改消息。") }
        .confirmationDialog("删除本机对话？", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("删除", role: .destructive) { if let id = deleteID { store.delete(id) }; deleteID = nil }
        } message: { Text("只删除本机记录，不删除服务器任务。") }
    }
}

struct TasksView: View {
    @EnvironmentObject private var store: ChatStore
    let open: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("执行中心").font(.title.bold())
                Text("进度、授权与最近结果").foregroundStyle(.secondary)
                NavigationLink { CronTasksView() } label: {
                    Label("定时安排 · 查看与管理", systemImage:"calendar.badge.clock")
                }.accessibilityIdentifier("cron-navigation")
                NavigationLink { RunHistoryView() } label: {
                    Label("执行记录 · 本机与登记", systemImage:"clock.arrow.circlepath")
                }.accessibilityIdentifier("run-history-navigation")
                if store.busy { RunCard() }
                else { Label("当前没有进行中的任务", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                Text("最近执行 · 每个对话的最新任务").font(.headline)
                ForEach(store.chats.filter { $0.run != nil }) { chat in
                    Button { store.selected = chat.id; open() } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(chat.title).font(.headline)
                            Label(chat.run!.label, systemImage: chat.run!.status == "completed" ? "checkmark.circle" : chat.run!.terminal ? "exclamationmark.circle" : "clock")
                            Text(RecentPreview.date(chat.run!.createdAt)).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }.padding(22)
        }.navigationTitle("任务").navigationBarTitleDisplayMode(.inline)
    }
}

struct RunCard: View {
    @EnvironmentObject private var store: ChatStore
    @State private var stopKey: String?
    @State private var approvalIntent: ApprovalIntent?
    private struct ApprovalIntent { let key: String; let requestID: String; let choice: String }
    var body: some View {
        if let run = store.activeRun, !run.terminal {
            VStack(alignment: .leading, spacing: 12) {
                Label(run.label, systemImage: run.status == "waiting_for_approval" ? "hand.raised" : "clock").font(.headline)
                if let chat = store.activeChat { Text(chat.title).font(.subheadline).lineLimit(2) }
                Text(store.connected ? "已核实服务器状态" : "连接待核实 · 不代表任务停止").font(.caption).foregroundStyle(.secondary)
                if let approval = run.approval, run.status == "waiting_for_approval" {
                    Text(approval.command ?? approval.description ?? "服务器请求批准").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Text("请阅读操作后决定，仅对这一次请求有效。").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        if let requestID = approval.request_id, approval.choices?.contains("deny") == true { Button("拒绝", role: .destructive) { approvalIntent = ApprovalIntent(key: run.key, requestID: requestID, choice: "deny") }.accessibilityIdentifier("approval-deny") }
                        if let requestID = approval.request_id, approval.choices?.contains("once") == true { Button { approvalIntent = ApprovalIntent(key: run.key, requestID: requestID, choice: "once") } label: { Text("仅批准本次…").fixedSize(horizontal: false, vertical: true) }.accessibilityIdentifier("approval-once") }
                    }.buttonStyle(.bordered).disabled(store.approvalBusy || !store.connected)
                    if approval.request_id == nil { Text("服务器未提供精确请求编号，不能安全作答。请等待服务端更新状态。").font(.caption) }
                }
                if !store.toolProgress.isEmpty { Text(store.toolProgress).font(.caption).textSelection(.enabled) }
                if run.stopRequested { Text("停止请求待确认；执行器仍可能运行。").font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("手动重连") { store.resume() }
                    Spacer()
                    Button("停止…", role: .destructive) { stopKey = run.key; DiagnosticLog.shared.record(.stopPrompt) }
                }.buttonStyle(.bordered)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
            .confirmationDialog("确认回答这一次操作请求？", isPresented: Binding(get: { approvalIntent != nil }, set: { if !$0 { approvalIntent = nil } }), titleVisibility: .visible) {
                Button(approvalIntent?.choice == "once" ? "确认仅批准本次" : "确认拒绝", role: approvalIntent?.choice == "deny" ? .destructive : nil) {
                    if let intent = approvalIntent { store.approve(intent.choice, expectedKey: intent.key, expectedRequestID: intent.requestID) }; approvalIntent = nil
                }
                Button("取消", role: .cancel) { approvalIntent = nil }
            } message: { Text("不允许会话级或永久授权。若服务器请求已变化，本次回答将拒绝发送。") }
            .confirmationDialog("停止当前服务器任务？", isPresented: Binding(get: { stopKey != nil }, set: { if !$0 { stopKey = nil } }), titleVisibility: .visible) {
                Button("确认停止", role: .destructive) { if stopKey == store.activeRun?.key { store.cancel() }; stopKey = nil }
                Button("继续等待", role: .cancel) { stopKey = nil; DiagnosticLog.shared.record(.stopDismissed) }
            } message: { Text("切换页面和离开前台不需要停止。") }
        }
    }
}

// iOS adaptation of the Android TasksScreen COMPLETED (记录) tab: local
// captured history plus a metadata-only server page. Browsing is read-only and
// never changes the active run or stop target.
struct RunHistoryView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var entries: [RunHistoryStore.Entry] = []
    @State private var query = ""
    @State private var statusFilter: String = ""
    @State private var serverPage: RunHistoryStore.ServerPage?
    @State private var serverError: String?
    @State private var busy = false
    private let store2 = RunHistoryStore()
    private let api = HermesAPI()
    private var statuses: [String] { ["", "completed", "failed", "cancelled", "interrupted"] }
    private var filtered: [RunHistoryStore.Entry] {
        RunHistoryStore.filter(entries, query: query, status: statusFilter.isEmpty ? nil : statusFilter, before: nil)
    }
    var body: some View {
        List {
            Section {
                Text("本机记录 · 不是完整服务器历史").font(.headline)
                Text("这里只保留此 App 实际发出并已结束的任务；不含定时安排的执行，也不自动拉取服务器输出。").font(.caption).foregroundStyle(.secondary)
                TextField("搜索标题或结果", text: $query)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("history-search")
                Picker("状态", selection: $statusFilter) {
                    Text("全部").tag("")
                    Text("已完成").tag("completed")
                    Text("失败").tag("failed")
                    Text("已取消").tag("cancelled")
                    Text("已中断").tag("interrupted")
                }.pickerStyle(.segmented)
            }
            if filtered.isEmpty { Text("还没有已结束的任务记录").foregroundStyle(.secondary) }
            ForEach(filtered) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(entry.chatTitle).font(.headline); Spacer(); Text(RunHistoryStore.Entry.sourceLabel(entry.source)).font(.caption2).foregroundStyle(.secondary) }
                    Label(entry.run.label, systemImage: entry.run.status == "completed" ? "checkmark.circle" : entry.run.terminal ? "exclamationmark.circle" : "clock").font(.subheadline)
                    Text(RecentPreview.date(entry.capturedAt)).font(.caption).foregroundStyle(.secondary)
                    if let output = entry.run.output { Text(RecentPreview.text(output)).font(.caption).lineLimit(3).foregroundStyle(.secondary) }
                }.padding(.vertical, 4)
            }
            serverHistorySection
        }.navigationTitle("执行记录").navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }.task { await reload() }
        .onChange(of: store.settings.serverURL) { _ in serverPage = nil; Task { await reload() } }
    }
    // Metadata-only server page: run IDs and creation order for runs created
    // through this app boundary. No output, no automatic per-run fetching.
    @ViewBuilder private var serverHistorySection: some View {
        Section("服务器登记 · 此 App 创建的任务编号") {
            if busy { ProgressView() }
            if let serverError { Text(serverError).font(.caption).foregroundStyle(.secondary) }
            if let page = serverPage {
                if page.items.isEmpty { Text("服务器暂无此 App 的任务登记").font(.caption).foregroundStyle(.secondary) }
                ForEach(page.items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.run_id).font(.caption.monospaced()).textSelection(.enabled)
                        Text("仅登记信息；点按不会拉取输出").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if page.next_cursor != nil {
                    Button("载入更早的登记") { Task { await loadOlder() } }.disabled(busy)
                }
            }
        }
    }
    @MainActor private func reload() async {
        busy = true; defer { busy = false }
        entries = (try? store2.load()) ?? []
        do {
            let data = try await api.runRequest(store.settings, path: "app/runs?limit=50")
            serverPage = try JSONDecoder().decode(RunHistoryStore.ServerPage.self, from: data)
            serverError = nil
        } catch {
            serverPage = nil
            serverError = "服务器登记接口未开放（受限网关未更新时不可用）；本机记录不受影响。"
        }
    }
    @MainActor private func loadOlder() async {
        guard let cursor = serverPage?.next_cursor, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let data = try await api.runRequest(store.settings, path: "app/runs?limit=50&before=\(cursor)")
            let older = try JSONDecoder().decode(RunHistoryStore.ServerPage.self, from: data)
            serverPage = RunHistoryStore.ServerPage(items: (serverPage?.items ?? []) + older.items, next_cursor: older.next_cursor)
        } catch { serverError = "载入更早记录失败。" }
    }
}

@MainActor struct ConversationDetail: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var taskDetails = false
    @StateObject private var voice = VoiceInputModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var voiceBase = ""
    @State private var voiceChatID: UUID?
    @State private var quote: MessageQuote?
    private struct FileContext: Identifiable {
        let id: UUID
        let settings: ConnectionSettings
    }
    @State private var fileContext: FileContext?
    @State private var fileJump: UUID?
    @State private var projectContext: ProjectSelectionContext?
    var body: some View {
        VStack(spacing: 0) {
            Button {
                if let id=store.current?.id { projectContext=ProjectSelectionContext(id:id,settings:store.settings) }
            } label: {
                Label("项目：\(store.current?.workspaceProjectName ?? "默认工作区")",systemImage:"folder")
                    .font(.caption).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal).padding(.vertical,6)
            }.accessibilityIdentifier("chat-project-selector")
            ReadingMessageScroll(revision: "\(store.current?.messages.count ?? 0)-\(store.current?.messages.last?.content ?? "")", conversationID: store.current?.id, jumpTarget: fileJump) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if store.current?.messages.isEmpty != false { Text("跟球球说说，今天想做什么？").font(.title3).foregroundStyle(.secondary).padding(.vertical, 40) }
                        ForEach(store.current?.messages ?? []) { message in
                            VStack(alignment: .leading, spacing: 10) {
                                if fileJump == message.id { Text("已定位来源消息").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("file-source-located") }
                                HStack { Label(message.role == "user" ? "你" : "球球", systemImage: message.role == "user" ? "person.crop.circle" : "sparkles").font(.caption.bold()).foregroundStyle(.secondary); Spacer(); Button { UIPasteboard.general.string = message.content } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("复制消息").disabled(message.content.isEmpty) }
                                if let names = message.attachmentNames { ForEach(names, id: \.self) { name in Label(name, systemImage:"paperclip").font(.caption) } }
                                if message.interrupted == true { Text("未完成的回复").font(.caption).foregroundStyle(.orange) }
                                if message.content.isEmpty { Text(store.current?.run?.terminal == false ? "等待球球回复…" : "未收到回复（已停止或请求失败）").foregroundStyle(.secondary) }
                                else { MarkdownMessage(content: message.content) }
                                if let snapshot = message.quote { quotePreview(snapshot, removable: false) }
                                if ["user", "assistant"].contains(message.role), !message.content.isEmpty {
                                    Button { selectQuote(message) } label: { Label("引用", systemImage: "quote.bubble") }.buttonStyle(.borderless).contextMenu { Button("引用这条消息") { selectQuote(message) } }.accessibilityIdentifier("reply-quote")
                                }
                                if message.role == "assistant", (message.content.contains("MEDIA:") || message.content.contains("QIUQIU_FILE:")), let runID = message.artifactRunID ?? (store.current?.run?.replyID == message.id ? store.current?.run?.runID : nil) {
                                    ReplyArtifactsView(runID: runID, settings: store.settings)
                                }
                            }.id(message.id).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(message.role == "user" ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
                            .background(MessageQuoteSwipe { selectQuote(message) })
                        }
                    }.padding(18)
            }
            if store.busy {
                Button { taskDetails = true } label: {
                    Label("任务详情", systemImage:"clock").font(.subheadline)
                }.accessibilityLabel("当前任务 · 查看详情").frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal)
                    .sheet(isPresented: $taskDetails) {
                        NavigationStack { ScrollView { RunCard().padding() }.navigationTitle("当前任务").navigationBarTitleDisplayMode(.inline).toolbar { Button("返回对话") { taskDetails = false } } }
                    }
            }
            if let state = store.syncState[store.current?.id ?? UUID()], let chatID = store.current?.id, store.current?.sessionID != nil {
                // Honest sync status: "live" only means latest check succeeded; assistant
                // streaming tokens are not persisted by the server, so replies appear
                // when turns finalize, not token-by-token.
                HStack(spacing: 6) {
                    switch state {
                    case "busy": Image(systemName: "hourglass"); Text("原渠道正在进行对话，等待其完成后再继续").font(.caption)
                    case "stale": Image(systemName: "bolt.slash"); Text("同步已过期，尚未核实最新消息").font(.caption)
                    case "loading": ProgressView().controlSize(.mini); Text("正在检查更新…").font(.caption)
                    default: Image(systemName: "checkmark.icloud"); Text("已同步至最新存储消息（流式输出未落库，回复在整轮结束后出现）").font(.caption2)
                    }
                }.foregroundStyle(state == "busy" ? .orange : .secondary).frame(maxWidth: .infinity).padding(6)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("sync-state-\(state)")
                    .accessibilityLabel("同步状态·\(state)")
                    .id("\(state)-\(chatID)")
            }
            if let error = store.error { HStack { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled); Button("关闭") { store.error = nil } }.padding(10) }
            if let quote { quotePreview(quote, removable: true).padding(.horizontal) }
            inlineVoiceStatus
            ChatAttachmentPicker()
            HStack(alignment: .bottom) {
                Button {
                    guard !voiceActive else { return }
                    voiceBase = draft; voiceChatID = store.current?.id
                    Task { await voice.start() }
                } label: {
                    Image(systemName: "mic").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("语音输入 · 转为文字草稿")
                    .accessibilityIdentifier("voice-input")
                    .disabled(store.current?.archived == true || store.attachmentLoading || voiceActive)
                TextField(store.busy ? "任务进行中，结束后可发送" : "跟球球说…", text: Binding(get: { draft }, set: { value in if voiceActive { voice.cancel(); voiceChatID = nil }; draft = value }), axis: .vertical).lineLimit(1...6).padding(12).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                Button { let previous = store.current?.run?.key; store.send(draft, quote: quote); if store.current?.run?.key != previous { draft = ""; quote = nil; voiceChatID = nil } } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("发送").disabled(voiceActive || !store.canSend || store.attachmentLoading || store.current?.archived == true || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty))
            }.padding()
        }.navigationTitle(store.current?.title ?? "球球").navigationBarTitleDisplayMode(.inline)
        .sheet(item:$projectContext) { context in NavigationStack { ProjectSelector(chatID:context.id,settings:context.settings) } }
        .sheet(item: $fileContext) { context in
            NavigationStack {
                ConversationFilesView(chatID: context.id, settings: context.settings) { source in
                    guard let messageID = try? store.locateFileSource(source, settings: context.settings) else { return false }
                    fileJump = messageID
                    fileContext = nil
                    return true
                }.toolbar { Button("关闭文件列表") { fileContext = nil } }
            }
        }
        .onChange(of: voice.session.transcript) { text in
            guard voiceChatID == store.current?.id, voice.session.phase != .cancelled else { return }
            draft = voiceBase + (voiceBase.isEmpty || text.isEmpty ? "" : "\n") + text
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { voice.cancel(source: 12); voiceChatID = nil }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { break }
                voice.session.tick(at: VoiceInputModel.now)
            }
        }
        .onAppear { if let chat = store.current, chat.sessionID != nil { store.startSync(for: chat.id) } }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--ui-typography-stream") else { return }
            for index in 0..<30 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, let id = store.selected, let c = store.chats.firstIndex(where: { $0.id == id }), !store.chats[c].messages.isEmpty else { return }
                store.chats[c].messages[0].content += "  let streamed\(index) = \(index)\n"
            }
        }
        #endif
        .onDisappear { voice.cancel(source: 13); voiceChatID = nil; store.stopSync() }
        .onChange(of: store.current?.id) { _ in voice.cancel(); voiceChatID = nil; quote = nil; draft = ""; if let chat = store.current, chat.sessionID != nil { store.startSync(for: chat.id) } else { store.stopSync() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { if let id = store.current?.id { fileJump = nil; fileContext = FileContext(id: id, settings: store.settings) } } label: { Label("对话文件", systemImage: "folder") }.accessibilityIdentifier("conversation-files")
            }
            ToolbarItem(placement: .confirmationAction) { Button("完成") { store.stopSync(); dismiss() } }
        }
    }
    private var voiceActive: Bool { [.authorizing, .recording, .finishing].contains(voice.session.phase) }
    private func selectQuote(_ message: ChatMessage) {
        guard let id = store.current?.id else { return }
        quote = MessageQuote.capture(message, conversationID: id)
    }
    private func quotePreview(_ snapshot: MessageQuote, removable: Bool) -> some View {
        HStack(alignment: .top) {
            Rectangle().fill(Color.secondary).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("引用 · " + snapshot.senderLabel).font(.caption.bold())
                Text(snapshot.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if removable { Button { quote = nil } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("取消引用").accessibilityIdentifier("quote-cancel") }
        }.fixedSize(horizontal: false, vertical: true).padding(8).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    @ViewBuilder private var inlineVoiceStatus: some View {
        if voice.session.phase != .idle {
            VStack(alignment: .leading, spacing: 6) {
                Text(voice.statusText).font(.caption).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("voice-status")
                if voiceActive {
                    HStack {
                        if voice.session.phase == .recording {
                            Button("停止录音") { voice.session.stop(at: VoiceInputModel.now) }.accessibilityIdentifier("voice-stop")
                        }
                        Button("取消语音") { voice.cancel(); draft = voiceBase; voiceChatID = nil }.accessibilityIdentifier("voice-cancel")
                    }.buttonStyle(.bordered)
                }
                if voice.session.phase == .failed, voice.session.permission != .allowed {
                    Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 8)
        }
    }
}

struct MarkdownMessage: View {
    let content: String
    @State private var externalURL: URL?
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MessageBlock.parse(content)) { block in
                MessagePresentationBlock(block: block)
            }
        }.font(.body).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard let safe = ReplyLink.external(url.absoluteString) else { return .discarded }
            externalURL = safe; return .handled
        })
        .confirmationDialog("在浏览器打开外部链接？", isPresented: Binding(get: { externalURL != nil }, set: { if !$0 { externalURL = nil } }), titleVisibility: .visible) {
            Button("打开浏览器") { if let url = externalURL { openURL(url) }; externalURL = nil }
            Button("取消", role: .cancel) { externalURL = nil }
        } message: { Text("外部内容不会自动下载，也不会附带 App 的认证令牌。\n" + (externalURL?.host ?? "")) }
    }
}
#endif
