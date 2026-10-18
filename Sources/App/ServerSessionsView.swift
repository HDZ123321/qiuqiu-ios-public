import SwiftUI
#if SWIFT_PACKAGE
import HermesCore
#endif

// Explicit read actions only; never submit a run while browsing or opening.
struct ServerSessionsView: View {
    @EnvironmentObject private var store: ChatStore
    let open: () -> Void
    @State private var items: [ServerSessionItem] = []
    @State private var next: Int?
    @State private var loaded = false
    @State private var loading = false
    @State private var opening: String?
    @State private var error: String?
    @State private var unavailable: ServerSessionItem?
    @State private var operation: Task<Void, Never>?
    @State private var epoch = UUID()
    private let api = HermesAPI()
    var body: some View {
        List {
            Section {
                Text("仅显示当前 App 专用入口登记的会话，不包括微信等其他渠道。同一入口和令牌可能包含其他安装的会话。")
                Text("点击标题直接读取最新存储文字并打开，不会发送消息。原生标题优先；无标题时使用首条用户文字摘要，无法追溯仅保存在旧设备的改名。")
                Button(loaded ? "重新获取列表" : "获取服务器会话") { Task { await fetch(reset: true) } }.disabled(loading || opening != nil)
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }.font(.footnote)
            ForEach(items) { item in
                Button { beginOpen(item) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localTitle(item) ?? item.displayTitle).font(.headline)
                            Text("App 登记 · \(item.run_count) 次任务").font(.caption).foregroundStyle(.secondary)
                            if item.title_source == "first_user" { Text("首条用户文字摘要").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if opening == item.id { ProgressView().accessibilityLabel("正在读取历史") }
                    }
                }.disabled(opening != nil || loading)
                    .accessibilityIdentifier("server-session-" + item.id)
            }
            if loaded && items.isEmpty { Text("此 App 入口尚无登记会话。") }
            if next != nil { Button("加载更多会话") { Task { await fetch(reset: false) } }.disabled(loading || opening != nil) }
        }.navigationTitle("服务器会话")
        .onChange(of: store.settings) { _ in invalidate(); items = []; next = nil; loaded = false }
        .onDisappear { invalidate() }
        .alert("历史文字不可用", isPresented: Binding(get: { unavailable != nil }, set: { if !$0 { unavailable = nil } })) {
            Button("取消", role: .cancel) { unavailable = nil }
            Button("仅按编号继续") {
                guard let item = unavailable else { return }
                do { try store.openServerSession(item, pages: []); unavailable = nil; open() }
                catch { self.error = "无法保存本机会话，请重试。" }
            }
        } message: {
            Text("服务器未存储可安全读取的文字，或原会话已转移。不会生成空白历史冒充原对话。可仅按编号准备继续，手动发送才会开始任务。")
        }
    }
    private func localTitle(_ item: ServerSessionItem) -> String? {
        store.chats.first { $0.sessionID == item.id && ($0.serverSource == nil || $0.serverSource?.scope == ServerSessionImport.scope(store.settings)) }?.title
    }
    @MainActor private func invalidate() {
        epoch = UUID(); operation?.cancel(); operation = nil; opening = nil; loading = false; unavailable = nil
    }
    @MainActor private func beginOpen(_ item: ServerSessionItem) {
        guard opening == nil, !loading else { return }
        opening = item.id; error = nil
        let token = epoch, configuration = store.settings
        let identity = ServerSessionImport.scope(configuration)
        operation = Task { @MainActor in
            defer { if token == epoch { opening = nil; operation = nil } }
            do {
                let pages = try await api.sessionTranscript(configuration, id: item.id)
                guard !Task.isCancelled, token == epoch, identity == ServerSessionImport.scope(store.settings) else { return }
                let hasHistory = pages.allSatisfy { $0.history == "stored_text" } && pages.contains { !$0.items.isEmpty }
                let hasLocal = store.chats.contains { $0.sessionID == item.id && !$0.messages.isEmpty && ($0.serverSource == nil || $0.serverSource?.scope == identity) }
                guard hasHistory || hasLocal else { unavailable = item; return }
                try store.openServerSession(item, pages: pages)
                open()
            } catch {
                guard !Task.isCancelled, token == epoch else { return }
                self.error = "历史读取失败（代码 \((error as NSError).code)），未修改本机对话。点会话可重试。"
            }
        }
    }
    @MainActor private func fetch(reset: Bool) async {
        guard !loading, opening == nil else { return }
        let token = epoch, configuration = store.settings
        loading = true; error = nil
        defer { if token == epoch { loading = false } }
        do {
            let data = try await api.sessionRead(configuration, cursor: reset ? nil : next)
            guard !Task.isCancelled, token == epoch, ServerSessionImport.scope(configuration) == ServerSessionImport.scope(store.settings) else { return }
            let page = try JSONDecoder().decode(ServerSessionPage.self, from: data)
            var seen = Set<String>()
            items = ((reset ? [] : items) + page.items).filter { seen.insert($0.id).inserted }
            next = page.next_cursor; loaded = true
        } catch {
            if token == epoch { self.error = "未能读取会话（代码 \((error as NSError).code)）。请重试。" }
        }
    }
}
