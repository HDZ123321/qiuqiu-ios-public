#if os(iOS)
import SwiftUI

struct ConversationFilesView: View {
    @EnvironmentObject private var store: ChatStore
    let chatID: UUID
    let settings: ConnectionSettings
    let jump: (ConversationFiles.Source) -> Bool
    @State private var index = ConversationFiles.Index()
    @State private var loading = false
    @State private var error: String?
    @State private var unavailable = false
    @State private var revision = UUID()
    private let api = HermesAPI()
    var body: some View {
        List {
            Section {
                Text("仅显示本对话中有任务来源、且仍可从专用工作区读取的生成文件；不含未建立来源关联的手机附件或旧渠道文件。")
                    .font(.caption).foregroundStyle(.secondary)
                if loading { ProgressView("正在读取文件…").accessibilityIdentifier("conversation-files-loading") }
                if let error { Text(error).foregroundStyle(.secondary) }
                if !loading && index.items.isEmpty {
                    Text(unavailable ? "此对话没有可核实的文件来源" : "暂无可访问的生成文件")
                }
            }
            if !index.items.isEmpty {
                Section("本对话生成的文件") {
                    ForEach(index.items) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            ReplyArtifactCard(item: entry.artifact, runID: entry.source.runID, settings: settings)
                            Button { if !jump(entry.source) { error = "来源消息已删除、不可用或连接已变化。" } } label: {
                                Label("回到来源消息", systemImage: "arrow.uturn.backward")
                            }.accessibilityIdentifier("conversation-file-jump")
                        }.buttonStyle(.borderless).padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("对话文件").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { revision = UUID() } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(loading).accessibilityIdentifier("conversation-files-refresh") }
        .refreshable { await reload() }
        .task(id: revision) { await reload() }
    }
    @MainActor private func reload() async {
        guard !loading else { return }
        loading = true; error = nil; index = ConversationFiles.Index()
        defer { loading = false }
        guard let chat = store.chats.first(where: { $0.id == chatID }), ServerSessionImport.scope(settings) == ServerSessionImport.scope(store.settings), chat.serverSource == nil || chat.serverSource?.scope == ServerSessionImport.scope(settings) else {
            unavailable = true; return
        }
        let sources = ConversationFiles.sources(in: chat)
        unavailable = sources.isEmpty
        var result = ConversationFiles.Index()
        for source in sources {
            do {
                let items = try await api.replyArtifacts(settings, runID: source.runID)
                guard !Task.isCancelled, ServerSessionImport.scope(settings) == ServerSessionImport.scope(store.settings), store.chats.contains(where: { $0.id == chatID }) else { return }
                result.append(items, from: source)
            } catch is CancellationError { return }
            catch { self.error = "部分文件来源暂时无法读取，请刷新重试。" }
        }
        index = result
    }
}
#endif
