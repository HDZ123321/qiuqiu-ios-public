import SwiftUI
#if SWIFT_PACKAGE
import HermesCore
#endif

// Explicit reads only. No network work on appearance and no task submission here.
struct ServerSessionsView: View {
    @EnvironmentObject private var store: ChatStore
    let open: () -> Void
    @State private var items: [ServerSessionItem] = []
    @State private var next: Int?
    @State private var loaded = false
    @State private var loading = false
    @State private var error: String?
    @State private var scope: String?
    private let api = HermesAPI()
    var body: some View {
        List {
            Section {
                Text("仅显示通过当前 App 专用入口登记的会话；同一入口和令牌可能包含其他安装的 App 会话，不是本设备专属，也不包括微信等其他渠道。")
                Text("列表是持久登记元数据，不代表任务正在运行。历史需点选后单独读取；只展示实际存储的用户/助手文字，不含工具、思考、附件或完整项目。")
                Button(loaded ? "重新获取列表" : "获取服务器会话") { Task { await fetch(reset: true) } }.disabled(loading)
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }.font(.footnote)
            ForEach(items) { item in
                NavigationLink {
                    ServerSessionDetail(item: item, configuration: store.settings, open: open)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("服务器会话 · \(item.created_seq)").font(.headline)
                        Text(item.session_id).font(.caption).textSelection(.enabled)
                        Text("App 登记 · \(item.run_count) 次任务").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if loaded && items.isEmpty { Text("此 App 入口尚无登记会话。") }
            if next != nil { Button("加载更多会话") { Task { await fetch(reset: false) } }.disabled(loading) }
        }.navigationTitle("服务器会话")
        .onChange(of: store.settings) { _ in items = []; next = nil; loaded = false; scope = nil }
    }
    @MainActor private func fetch(reset: Bool) async {
        guard !loading else { return }
        let configuration = store.settings, identity = ServerSessionImport.scope(store.settings)
        loading = true; error = nil
        defer { loading = false }
        do {
            let data = try await api.sessionRead(configuration, cursor: reset ? nil : next)
            guard !Task.isCancelled, identity == ServerSessionImport.scope(store.settings) else { return }
            let page = try JSONDecoder().decode(ServerSessionPage.self, from: data)
            var seen = Set<String>()
            items = ((reset ? [] : items) + page.items).filter { seen.insert($0.id).inserted }
            next = page.next_cursor; loaded = true; scope = identity
        } catch { self.error = "未能读取会话（代码 \((error as NSError).code)）。请重试；404 可能表示服务器尚未启用专用会话入口。" }
    }
}

struct ServerSessionDetail: View {
    @EnvironmentObject private var store: ChatStore
    let item: ServerSessionItem
    let configuration: ConnectionSettings
    let open: () -> Void
    @State private var pages: [ServerSessionMessages] = []
    @State private var next: Int?
    @State private var loading = false
    @State private var error: String?
    private let api = HermesAPI()
    private var sameConnection: Bool { ServerSessionImport.scope(configuration) == ServerSessionImport.scope(store.settings) }
    var body: some View {
        List {
            Section("App 登记会话") {
                Text(item.session_id).font(.caption).textSelection(.enabled)
                Text("历史只读预览；打开时已有本机对话优先，绝不覆盖重命名、归档、消息或任务。继续时保留服务器会话编号，由服务器读取上下文；必须由你手动发送才会创建任务。")
                if !sameConnection { Text("连接已更换，请返回重新获取列表。").foregroundStyle(.red) }
                Button(pages.isEmpty ? "读取真实历史文字" : "重新读取历史") { Task { await fetch(reset: true) } }.disabled(loading || !sameConnection)
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                if pages.contains(where: { $0.history == "unavailable" }) {
                    Text("历史消息不可用：服务器未提供此会话的安全导出，或会话已压缩转移。不会从任务输出拼造历史；仍可仅按编号继续，由服务器处理上下文。")
                } else if pages.isEmpty {
                    Text("尚未读取历史。可只打开会话编号继续，不会伪造或自动补全历史。")
                } else {
                    Text(next == nil ? "已读取可导出的存储文字（不含工具/附件）。" : "仅已读取部分历史；请继续分页后再导入文字。")
                }
                Button("打开本机会话 / 准备继续") {
                    do {
                        // A partial page is preview only; never import an incomplete transcript.
                        try store.openServerSession(item, pages: next == nil ? pages : [])
                        open()
                    } catch { self.error = "无法保存本机会话，请重试。" }
                }.disabled(loading || !sameConnection)
            }.font(.footnote)
            Section("真实存储文字预览") {
                ForEach(Array(preview.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading) {
                        Text(message.role == "user" ? "你" : "助手").font(.caption).foregroundStyle(.secondary)
                        Text(message.content).textSelection(.enabled)
                    }
                }
                if next != nil { Button("读取下一页历史") { Task { await fetch(reset: false) } }.disabled(loading || !sameConnection) }
            }
        }.navigationTitle("服务器会话详情")
    }
    private var preview: [ServerSessionMessages.Item] {
        var seen = Set<String>()
        return pages.flatMap(\.items).filter { seen.insert($0.id).inserted }
    }
    @MainActor private func fetch(reset: Bool) async {
        guard !loading, sameConnection else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let data = try await api.sessionRead(configuration, id: item.id, messages: true, cursor: reset ? nil : next)
            guard !Task.isCancelled, sameConnection else { return }
            let page = try JSONDecoder().decode(ServerSessionMessages.self, from: data)
            guard page.session_id == item.id else { throw ClientError.message("身份不匹配") }
            pages = (reset ? [] : pages) + [page]; next = page.next_offset
        } catch { self.error = "历史读取失败（代码 \((error as NSError).code)），未修改本机对话。请重试，或仅按编号继续。" }
    }
}
