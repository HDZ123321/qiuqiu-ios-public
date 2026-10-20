#if os(iOS)
import SwiftUI

struct ProjectSelector: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    let chatID: UUID
    let settings: ConnectionSettings
    @State private var items: [WorkspaceProject]=[]
    @State private var name=""
    @State private var error: String?
    @State private var busy=false
    private let api=HermesAPI()
    private var chat: Chat? { store.chats.first { $0.id == chatID } }
    private var blocked: Bool { chat == nil || chat?.run?.terminal == false }
    var body: some View {
        List {
            Section {
                Text("当前对话：\(chat?.title ?? "已不可用")").font(.headline)
                if blocked { Text("此对话的任务尚未结束，结束后才能切换；原任务工作区保持不变。").foregroundStyle(.orange).accessibilityIdentifier("project-pending-block") }
                Text("用于此对话后续请求的附件与生成文件；旧文件留在原项目。").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("工作区范围说明") {
                    Text("App 管理的文件目录，不是服务器全局目录、系统挂载或终端执行隔离；不会修改原渠道历史或更换原会话编号。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red); Button("刷新项目") { Task { await load() } } } }
            Section("选择项目 · 绑定此对话") {
                ForEach(items) { item in
                    Button { bind(item) } label: {
                        HStack(alignment:.top) {
                            Text(item.name).fixedSize(horizontal:false,vertical:true)
                            Spacer()
                            if item.id == chat?.workspaceProjectID { Image(systemName:"checkmark") }
                        }
                    }.disabled(blocked || busy).accessibilityIdentifier("project-"+item.id)
                }
            }
            Section("新建项目") {
                TextField("项目名称",text:$name).accessibilityIdentifier("project-name")
                Button("创建并选择") { Task { await create() } }.disabled(blocked || busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("project-create")
                Text("只创建专用工作区内的独立子目录，不支持删除。名称不能包含路径、隐藏前缀或控制字符。").font(.caption).foregroundStyle(.secondary)
            }
            if busy { ProgressView() }
        }.navigationTitle("切换项目").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("取消") { dismiss() } }
        .task { await load() }
    }
    @MainActor private func load() async {
        busy=true;defer { busy=false }
        do { items=try await api.workspaceProjects(settings);error=nil }
        catch { self.error=error.localizedDescription }
    }
    private func bind(_ item: WorkspaceProject) {
        do {
            guard ServerSessionImport.scope(settings) == ServerSessionImport.scope(store.settings) else { throw ClientError.message("连接已变化，请重新打开项目列表。") }
            try store.bindWorkspace(item,chatID:chatID);dismiss()
        } catch { self.error=error.localizedDescription }
    }
    @MainActor private func create() async {
        busy=true;defer { busy=false }
        do {
            guard !blocked else { return }
            let item=try await api.createWorkspaceProject(settings,name:name)
            bind(item)
        } catch { self.error=error.localizedDescription }
    }
}
struct ProjectSelectionContext: Identifiable {
    let id: UUID
    let settings: ConnectionSettings
}
#endif
