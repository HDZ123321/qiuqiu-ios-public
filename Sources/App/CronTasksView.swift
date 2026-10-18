#if os(iOS)
import SwiftUI

// Native adaptation of Android TasksScreen scheduled section; no Dashboard auth.
struct CronTasksView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var jobs: [CronJob] = []
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var showPaused = false
    @State private var creating = false
    @State private var selected: CronJob?
    private let api=HermesAPI()
    var body: some View {
        List {
            Section {
                Text("服务器定时安排").font(.headline)
                Text("现有安排只显示安全摘要；只有此 App 创建的安排可以修改。新安排默认暂停。服务器未开放专用接口时不会改用管理接口。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("显示已暂停",isOn:$showPaused)
            }
            if let error { Section { Text(error).foregroundStyle(.red); Button("重试") { Task { await reload() } } } }
            if let notice { Text(notice).font(.caption) }
            if busy { ProgressView("正在读取…") }
            if jobs.isEmpty && !busy && error == nil { Text("还没有定时安排") }
            ForEach(jobs.filter { showPaused || $0.enabled }) { job in
                Button { selected=job } label: {
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Text(job.name).font(.headline); Spacer(); Text(job.enabled ? "已启用" : "已暂停").font(.caption) }
                        Text(job.schedule_display ?? "时间未提供").font(.subheadline)
                        Text(job.manageable ? "此 App 创建" : "仅查看 · 已有安排").font(.caption).foregroundStyle(.secondary)
                        if let next=job.next_run_at { Text("下次：\(next)").font(.caption) }
                        if let status=job.last_status { Text("最近结果：\(status)").font(.caption) }
                    }.foregroundStyle(.primary)
                }.disabled(busy)
            }
        }.navigationTitle("定时安排")
        .toolbar { Button { creating=true } label: { Label("新建",systemImage:"plus") }.disabled(busy) }
        .refreshable { await reload() }.task { await reload() }
        .sheet(isPresented:$creating,onDismiss:{ Task { await reload() } }) {
            NavigationStack { CronEditor(job:nil,settings:store.settings) { notice=$0 } }
        }
        .sheet(item:$selected,onDismiss:{ Task { await reload() } }) { job in
            NavigationStack { CronDetail(job:job,settings:store.settings) { notice=$0 } }
        }
        .onChange(of:store.settings.serverURL) { _ in jobs=[]; selected=nil; creating=false; Task { await reload() } }
        .onChange(of:store.settings.bearer) { _ in jobs=[]; selected=nil; creating=false; Task { await reload() } }
    }
    @MainActor private func reload() async {
        guard !busy else { return }; busy=true; defer { busy=false }
        let settings=store.settings
        do {
            let data=try await api.runRequest(settings,path:"cron")
            guard settings.serverURL == store.settings.serverURL, settings.bearer == store.settings.bearer else { return }
            jobs=try JSONDecoder().decode(CronListing.self,from:data).jobs; error=nil
        } catch { jobs=[]; self.error="定时接口不可用或读取失败。不会尝试管理接口。\n"+error.localizedDescription }
    }
}

struct CronDetail: View {
    @State var job: CronJob
    let settings: ConnectionSettings
    let completed: (String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var pending: CronAction?
    @State private var editing=false
    @State private var busy=false
    @State private var error: String?
    var body: some View {
        List {
            Section("安排") {
                Text(job.name).font(.headline)
                Text(job.schedule_display ?? "时间未提供")
                Text(job.enabled ? "已启用" : "已暂停")
                if let prompt=job.prompt { Text(prompt).textSelection(.enabled) }
                else { Text("已有安排仅提供安全摘要，不能从 App 更改或读取完整任务内容。") }
                if let next=job.next_run_at { Text("下次：\(next)") }
            }
            Section("最近执行摘要 · 非完整历史") {
                Text(job.last_run_at ?? "尚无执行时间")
                Text(job.last_status ?? "尚无结果")
                if let latest = job.latest_execution {
                    Label(latest.status ?? "未知状态", systemImage: latest.status == "completed" ? "checkmark.circle" : latest.status == "failed" ? "xmark.circle" : "clock").font(.caption)
                    if let claimed = latest.claimed_at { Text("开始领取：\(claimed)").font(.caption) }
                    if let finished = latest.finished_at { Text("结束：\(finished)").font(.caption) }
                    Text("仅显示安全的状态与时间；执行报错细节和输出内容不会发送到此设备。").font(.caption2).foregroundStyle(.secondary)
                }
                Text("调度成功不代表执行完成；完整执行历史将在后续迁移。结果仅保留服务器本地。") .font(.caption)
            }
            if let error { Text(error).foregroundStyle(.red) }
            if busy { ProgressView() }
            if job.manageable {
                Section("明确操作") {
                    Button("编辑安排") { editing=true }.disabled(job.enabled)
                    if job.enabled { Text("先暂停才能编辑，避免修改后未经确认自动运行。").font(.caption) }
                    Button(job.enabled ? "暂停…" : "启用…") { pending=job.enabled ? .disable : .enable }
                    Button("立即调度一次…") { pending = .run }
                    Button("删除安排…",role:.destructive) { pending = .delete }
                }.disabled(busy)
            }
        }.navigationTitle("安排详情").toolbar { Button("关闭") { dismiss() } }
        .confirmationDialog(pending?.title ?? "确认操作",isPresented:Binding(get:{pending != nil},set:{if !$0 { pending=nil }}),titleVisibility:.visible) {
            if let action=pending {
                Button(action.title,role:action == .delete ? .destructive : nil) { Task { await perform(action) } }
            }
            Button("取消",role:.cancel) { pending=nil }
        } message: { Text(pending?.warning ?? "") }
        .sheet(isPresented:$editing) { NavigationStack { CronEditor(job:job,settings:settings) { message in completed(message); dismiss() } } }
    }
    @MainActor private func perform(_ action:CronAction) async {
        guard !busy else { return }; busy=true; defer { busy=false }; pending=nil
        do {
            let command=CronCommand(action:action,job:job)
            let data=try await HermesAPI().runRequest(settings,path:command.path,method:"POST",body:try command.payload())
            if action == .delete { completed("安排已删除（不停止在途执行）。"); dismiss() }
            else { job=try JSONDecoder().decode(CronJob.self,from:data); completed(action == .run ? "已请求下一次调度；尚未核实执行结果。" : "已回读安排状态。") }
            error=nil
        } catch { self.error="操作未核实，请关闭并刷新后重新确认；不会自动重试。\n"+error.localizedDescription }
    }
}

struct CronEditor: View {
    let job:CronJob?
    let settings:ConnectionSettings
    let completed:(String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var prompt=""
    @State private var schedule=""
    @State private var confirming=false
    @State private var busy=false
    @State private var error:String?
    private var action:CronAction { job == nil ? .create : .edit }
    var body: some View {
        Form {
            Section("安排内容") {
                TextField("名称",text:$name)
                TextField("时间，如 every 2h 或 0 9 * * *",text:$schedule).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextEditor(text:$prompt).frame(minHeight:160).accessibilityLabel("任务内容")
                Text("计划按服务器时区解释。创建后暂停，不会自动执行；不支持脚本、服务器目录或外部投递覆盖。") .font(.caption)
            }.disabled(busy)
            if let error { Text(error).foregroundStyle(.red) }
            Button(action.title+"…") { confirming=true }.disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || schedule.isEmpty)
            if busy { ProgressView("正在提交并回读…") }
        }.navigationTitle(job == nil ? "新建安排" : "编辑安排")
        .toolbar { Button("取消") { dismiss() }.disabled(busy) }
        .interactiveDismissDisabled(busy)
        .onAppear { if let job { name=job.name; prompt=job.prompt ?? ""; schedule=job.schedule_display ?? "" } }
        .confirmationDialog(action.title,isPresented:$confirming,titleVisibility:.visible) {
            Button("确认"+action.title) { Task { await save() } }; Button("取消",role:.cancel) {}
        } message: { Text(action.warning+"\n名称："+name+"\n时间："+schedule) }
    }
    @MainActor private func save() async {
        guard !busy else { return }; busy=true; defer { busy=false }
        do {
            let command=CronCommand(action:action,job:job,name:name,prompt:prompt,schedule:schedule)
            let data=try await HermesAPI().runRequest(settings,path:command.path,method:"POST",body:try command.payload())
            let saved=try JSONDecoder().decode(CronJob.self,from:data)
            guard !saved.enabled else { throw ClientError.message("服务器未返回预期暂停状态。") }
            completed("已保存暂停的安排；尚未执行。"); dismiss()
        } catch { self.error="保存结果未核实。请返回列表刷新，避免重复创建；不会自动重试。\n"+error.localizedDescription }
    }
}
#endif
