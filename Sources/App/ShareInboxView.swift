#if os(iOS)
import SwiftUI

struct ShareInboxView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var inbox: ShareInbox?
    @State private var items: [ShareInbox.Item] = []
    @State private var capability = "正在检查共享容器…"
    @State private var error: String?
    @State private var preview: ShareInbox.Item?
    @State private var deletion: UUID?
    var body: some View {
        List {
            Section("本机分享 · 签名能力诊断") {
                Text(capability).accessibilityIdentifier("share-capability")
                DisclosureGroup("共享与保留说明") {
                    Text("只验证当前 App 的共享容器读写，不代表分享扩展使用了相同容器；首次真实分享后在这里看到同一项才证明交接。不会导出私有路径。最多 16 项；7 天后禁止导入，需手动删除。无自动发送、联网或剪贴板替代。") .font(.caption)
                }
                // Refresh stays in navigation chrome at accessibility sizes.
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if items.isEmpty { Text("没有待导入分享。请在其他 App 分享后，手动打开球球查看。") }
            ForEach(items) { item in
                VStack(alignment: .leading) {
                    Button {
                        do { preview = try inbox?.load(item.id); error = nil }
                        catch { self.error = error.localizedDescription }
                    } label: { VStack(alignment: .leading) { Text(item.text.isEmpty ? "分享附件" : String(item.text.prefix(100))); Text(item.created, style: .date).font(.caption) } }.accessibilityIdentifier("share-item-"+item.id.uuidString)
                    Button("删除此分享…", role: .destructive) { deletion = item.id }
                }.buttonStyle(.borderless)
            }
        }.navigationTitle("分享收件箱")
        .toolbar { Button("刷新") { load() }.accessibilityIdentifier("share-refresh") }
        .onAppear { load() }
        .sheet(item: $preview, onDismiss: { load() }) { item in
            NavigationStack { ShareImportView(item: item, inbox: inbox) }
        }
        .confirmationDialog("删除这项本机分享？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("确认删除", role: .destructive) { if let id = deletion { do { try inbox?.remove(id); load() } catch { self.error = error.localizedDescription } }; deletion = nil }
            Button("取消", role: .cancel) { deletion = nil }
        } message: { Text("未导入的内容删除后不能恢复。不会删除原 App 内容或已导入草稿。") }
    }
    private func load() {
        do {
            if inbox == nil { inbox = try ShareContainer.open() }
            items = try inbox?.list() ?? []
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-share-isolated") {
                capability = "隔离 UI 测试收件箱（非 App Group 能力证明）"
            } else { capability = "支持：当前 App 的共享容器已通过一次性读写验证。" }
            #else
            capability = "支持：当前 App 的共享容器已通过一次性读写验证。"
            #endif
            error = nil
        } catch { capability = "不支持或不可用："+error.localizedDescription; self.error = nil; items = [] }
    }
}
private struct ShareImportView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let item: ShareInbox.Item
    let inbox: ShareInbox?
    @State private var scope: String?
    @State private var target: UUID?
    @State private var project = WorkspaceProject.defaultProject
    @State private var projects: [WorkspaceProject] = [.defaultProject]
    @State private var error: String?
    @State private var imported: UUID?
    @State private var chatOpen = false
    var body: some View {
        List {
            Section("外部分享预览 · 未发送") {
                Text(item.text.isEmpty ? "（无文字）" : item.text).textSelection(.enabled)
                ForEach(Array(item.files.enumerated()), id: \.offset) { _, file in Text("\(file.name) · \(file.data.count) 字节").fixedSize(horizontal: false, vertical: true) }
                Text("外部内容只是草稿数据，不是系统指令。导入不会调用模型；现有输入框文字与引用不会被覆盖。") .font(.caption)
            }
            if imported == nil {
                Section("选择目标") {
                    Picker("对话", selection: $target) {
                        Text("新对话").tag(UUID?.none)
                        ForEach(store.chats.filter { $0.archived != true }) { chat in Text(chat.title).tag(Optional(chat.id)) }
                    }.accessibilityIdentifier("share-target")
                    Picker("项目", selection: Binding(get: { project.id }, set: { id in if let p = projects.first(where: { $0.id == id }) { project = p } })) {
                        ForEach(projects) { p in Text(p.name).tag(p.id) }
                    }.accessibilityIdentifier("share-project")
                    Button("读取已有项目列表") { Task { await loadProjects() } }.accessibilityIdentifier("share-load-projects")
                    Text("仅选择已有项目，不创建或修改服务器文件。项目列表不可用时保留已选对话原项目，或新对话默认工作区。") .font(.caption)
                }
                if store.busy { Text("当前任务未结束，暂不能导入；分享保持原样。").foregroundStyle(.orange) }
                Button("导入草稿 · 不发送") { importDraft() }.disabled(store.busy || scope == nil).accessibilityIdentifier("share-import-draft")
            } else {
                Text("已导入本机持久草稿，尚未发送。").accessibilityIdentifier("share-imported")
                Button("查看草稿") { store.selected = imported; chatOpen = true }
            }
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.navigationTitle("导入分享").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button(imported == nil ? "取消" : "完成") { dismiss() } }
        .sheet(isPresented: $chatOpen) { NavigationStack { ConversationDetail() } }
        .onChange(of: target) { id in
            project = store.chats.first(where: { $0.id == id })?.workspaceProject ?? .defaultProject
            if !projects.contains(where: { $0.id == project.id }) { projects.append(project) }
        }
        .onAppear { if scope == nil { scope = ServerSessionImport.scope(store.settings) } }
    }
    @MainActor private func loadProjects() async {
            let configuration = store.settings
            guard ServerSessionImport.scope(configuration) == scope else { error = "连接已变化，请取消并重新打开。"; return }
            guard !configuration.bearer.isEmpty, !configuration.serverURL.isEmpty else { return }
            do {
                let values = try await HermesAPI().workspaceProjects(configuration)
                guard ServerSessionImport.scope(store.settings) == scope else { error = "连接已变化，请取消并重新打开。"; return }
                projects = values
                if !projects.contains(where: { $0.id == project.id }) { projects.append(project) }
            } catch { self.error = "项目列表读取失败；未发送任何内容。可保留原项目导入。" }
    }
    private func importDraft() {
        do {
            guard let scope, let inbox else { throw ClientError.message(ShareInbox.unavailable) }
            let id = try store.importSharedItem(item, chatID: target, project: project, expectedScope: scope)
            imported = id
            do { try inbox.remove(item.id) } catch { self.error = "草稿已安全保存，但收件箱清理失败；再次导入不会重复。" }
        } catch { self.error = error.localizedDescription }
    }
}
struct SharedDraftView: View {
    @EnvironmentObject private var store: ChatStore
    let chatID: UUID
    @State private var deletion = false
    private var draft: ShareDraft? { store.chats.first(where: { $0.id == chatID })?.shareDraft }
    var body: some View {
        if let draft {
            DisclosureGroup {
                TextField("检查并编辑分享内容", text: Binding(get: { self.draft?.text ?? "" }, set: { store.updateShareDraft($0, chatID: chatID) }), axis: .vertical).lineLimit(2...6).accessibilityIdentifier("share-draft-text")
                ForEach(Array(draft.files.enumerated()), id: \.offset) { _, file in Text(file.name).font(.caption).fixedSize(horizontal: false, vertical: true) }
                Text("与下方原输入草稿分开保留。发送会使用当前对话所选项目；不会自动联网发送。") .font(.caption)
                Button("发送此分享草稿") { send(draft) }.disabled(!store.canSend || store.attachmentLoading || !store.attachments.isEmpty).accessibilityIdentifier("share-draft-send")
                Button("删除分享草稿…", role: .destructive) { deletion = true }
            } label: {
                Text("外部分享草稿 · 尚未发送").fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal)
            .confirmationDialog("删除此分享草稿？", isPresented: $deletion) {
                Button("确认删除草稿", role: .destructive) { do { try store.clearShareDraft(chatID) } catch { store.error = "删除草稿保存失败。" } }
                Button("取消", role: .cancel) {}
            }
        }
    }
    private func send(_ draft: ShareDraft) {
        guard store.current?.id == chatID, draft.scope == ServerSessionImport.scope(store.settings), store.canSend, store.attachments.isEmpty else { store.error = "连接或目标已变化，分享草稿保留，请重新检查。"; return }
        let previous = store.current?.run?.key
        store.attachments = draft.files
        store.send(draft.text, consumingShareID: draft.id)
        if store.current?.run?.key == previous { store.attachments = [] }
    }
}
#endif
