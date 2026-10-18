import SwiftUI

@main struct QiuQiuApp: App {
    @StateObject private var store = ChatStore()
    var body: some Scene { WindowGroup {
        CompanionView().environmentObject(store)
        #if DEBUG && targetEnvironment(simulator)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-dark") ? .dark : .light)
        #endif
    } }
}

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showChats = false
    @State private var stopConfirmation = false
    @State private var stopTarget: String?
    @FocusState private var inputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if let source = store.current?.serverSource {
                                Text(source.history == "stored_text" ? "服务器会话 · 已导入真实存储文字（不含工具/附件）" : "服务器会话 · 本机未导入历史消息；继续由服务器读取上下文，不会自动发送。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if store.current?.messages.isEmpty != false && store.current?.serverSource == nil {
                                Text("先在设置中填写你自己的 HTTPS Hermes 服务地址与令牌，然后开始对话。此应用不附带服务器。")
                                    .foregroundStyle(.secondary).padding()
                            }
                            ForEach(store.current?.messages ?? []) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == "user" ? "你" : "球球").font(.caption).foregroundStyle(.secondary)
                                    if message.interrupted == true { Text("未完成的回复").font(.caption).foregroundStyle(.orange) }
                                    Text(message.content.isEmpty ? (store.busy && message.id == store.current?.messages.last?.id ? "等待球球回复…" : "未收到回复（已停止或请求失败）") : message.content).textSelection(.enabled)
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12)).id(message.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding()
                    }
                    .onChange(of: store.current?.messages.last?.content) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
                if store.busy {
                    TimelineView(.periodic(from: store.startedAt, by: 1)) { context in
                        HStack {
                            ProgressView()
                            Text("\(store.activeRun?.label ?? "执行中") · \(Int(context.date.timeIntervalSince(store.startedAt))) 秒").font(.caption)
                            Spacer()
                            Button("停止…", role: .destructive) { stopTarget = store.activeRun?.key; stopConfirmation = true; DiagnosticLog.shared.record(.stopPrompt) }
                        }.padding(8)
                    }
                }
                if let run = store.activeRun {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(run.label).font(.caption.bold())
                        if !run.terminal { Text(store.connected ? "已核实服务器状态" : "离线/重连中 · 不代表任务已停止").font(.caption) }
                        if let approval = run.approval, run.status == "waiting_for_approval" {
                            Text(approval.command ?? approval.description ?? "服务器请求批准").font(.caption).textSelection(.enabled)
                            HStack {
                                if approval.request_id != nil && approval.choices?.contains("deny") == true { Button("拒绝", role: .destructive) { store.approve("deny") } }
                                if approval.request_id != nil && approval.choices?.contains("once") == true { Button("仅批准本次") { store.approve("once") } }
                            }.disabled(store.approvalBusy)
                        }
                        if run.stopRequested { Text("停止请求待发送/确认；不等于服务器已停止。").font(.caption).foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !store.toolProgress.isEmpty {
                    VStack(alignment: .leading) {
                        Text("工具进度").font(.caption.bold())
                        Text(store.toolProgress).font(.caption).lineLimit(5).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color.orange.opacity(0.1))
                }
                if let error = store.error {
                    HStack(alignment: .top) {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        Spacer()
                        Button("关闭") { store.error = nil }
                    }.padding(8)
                }
                HStack(alignment: .bottom) {
                    TextField("消息", text: $draft, axis: .vertical).focused($inputFocused).lineLimit(1...6).textFieldStyle(.roundedBorder)
                    if store.busy { Button("停止…", role: .destructive) { stopTarget = store.activeRun?.key; stopConfirmation = true; DiagnosticLog.shared.record(.stopPrompt) } }
                    else {
                        Button("发送") {
                            let text = draft
                            store.send(text)
                            if store.busy { draft = ""; inputFocused = false }
                        }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding()
            }
            .navigationTitle(store.current?.title ?? "QiuQiu").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button { showChats = true } label: { Image(systemName: "list.bullet") }.disabled(store.busy).accessibilityLabel("对话列表") }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { store.newChat() } label: { Image(systemName: "square.and.pencil") }.disabled(store.busy).accessibilityLabel("新对话")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }.disabled(store.busy).accessibilityLabel("设置")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(store: store) }
            .sheet(isPresented: $showChats) {
                NavigationStack {
                    List {
                        ForEach(store.chats) { chat in
                            Button(chat.title) { store.selected = chat.id; store.toolProgress = ""; showChats = false }
                                .swipeActions { Button("删除", role: .destructive) { store.delete(chat.id) } }
                        }
                    }.navigationTitle("本地对话").toolbar { Button("完成") { showChats = false } }
                }
            }
            .confirmationDialog("停止当前服务器任务？", isPresented: $stopConfirmation, titleVisibility: .visible) {
                Button("确认停止", role: .destructive) {
                    guard let stopTarget, stopTarget == store.activeRun?.key else { return }
                    store.cancel()
                }
                Button("继续等待", role: .cancel) { DiagnosticLog.shared.record(.stopDismissed) }
            } message: { Text("离开前台不需要停止，回来会继续核实任务。") }
            .onAppear { store.resume() }
            .onChange(of: scenePhase) { phase in
                store.sceneChanged(phase)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var value: ConnectionSettings
    @State private var status = "未验证"
    @State private var checking = false
    @State private var verification = ConnectionVerification()
    @State private var checkTask: Task<Void, Never>?
    @State private var exportURL: URL?
    private let probeAPI = HermesAPI()
    init(store: ChatStore) { self.store = store; _value = State(initialValue: store.settings) }
    var body: some View {
        NavigationStack {
            Form {
                Section("球球连接") {
                    TextField("https://your-server", text: $value.serverURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Bearer Token", text: $value.bearer).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("模型 ID", text: $value.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                }.disabled(!store.canEditConnection)
                Section {
                    Button(checking ? "验证中…" : "验证连接与真实聊天") {
                        let configuration = value
                        let attempt = verification.begin()
                        checking = true; status = "正在验证鉴权…"
                        checkTask = Task {
                            defer { checking = false }
                            do {
                                _ = try await store.check(configuration)
                                try Task.checkCancellation()
                                guard value == configuration else { return }
                                verification.authenticated(attempt)
                                DiagnosticLog.shared.record(.auth)
                                status = "鉴权通过，正在验证聊天…"
                                try await probeAPI.verifyChat(configuration) {
                                    guard value == configuration, verification.complete(attempt) else { return }
                                    status = "聊天验证通过（\(Date().formatted(date: .omitted, time: .standard))）"
                                }
                            } catch {
                                guard value == configuration else { return }
                                verification.fail(attempt)
                                status = "未连接：验证失败或已取消（代码 \((error as NSError).code)）。可导出诊断日志。"
                            }
                        }
                    }.disabled(checking || !store.canEditConnection)
                    if checking { Button("取消验证") { checkTask?.cancel() } }
                    if !status.isEmpty { Text(status).font(.footnote).textSelection(.enabled) }
                } footer: {
                    Text("验证会发送一次简短聊天请求，可能消耗少量额度；不进入本地聊天记录，不自动重试。通过仅表示该时间点已收到文字及完成信号，并非持续在线。")
                }
                Section {
                    Button("导出诊断日志") {
                        do { exportURL = try DiagnosticLog.shared.export() }
                        catch { status = "日志导出失败。" }
                    }
                    if let exportURL { ShareLink("分享诊断日志", item: exportURL) }
                    Button("清空诊断日志", role: .destructive) { DiagnosticLog.shared.clear(); exportURL = nil }
                    Text("只记录时间、版本、请求编号、状态与计数；不记录令牌、聊天文字或工具内容。无自动上传；仅在你分享时导出。可通过微信发送给球球分析。 ").font(.caption)
                } header: { Text("本地诊断") } footer: {
                    Text("仅 HTTPS；可填写域名根地址或以 /v1 结尾的地址。地址与令牌保存在本机钥匙串。聊天文件不包含连接设置，但消息本身可能包含敏感内容。离开前台只断开连接，返回后核实服务器任务；停止会请求服务器协作停止，显示取消前执行器仍可能运行。服务重启可能中断任务。")
                }
            }
            .navigationTitle("设置")
            .onChange(of: value) { _ in
                checkTask?.cancel(); verification.invalidate(); status = "未验证（设置已修改）"
            }
            .onDisappear { checkTask?.cancel(); verification.invalidate() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try store.saveSettings(value); verification.invalidate(); dismiss() } catch { status = error.localizedDescription }
                    }.disabled(checking || !store.canEditConnection)
                }
            }
        }
    }
}
