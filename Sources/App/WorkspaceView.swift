#if os(iOS)
import SwiftUI
import QuickLook
import PDFKit
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var projectContext: ProjectSelectionContext?
    var body: some View {
        WorkspaceBrowser(settings:store.settings,project:store.current?.workspaceProject ?? .defaultProject,chatTitle:store.current?.title ?? "新对话",choose:{
            if let id=store.current?.id { projectContext=ProjectSelectionContext(id:id,settings:store.settings) }
        })
        .id("\(store.current?.id.uuidString ?? "none")-\(store.current?.workspaceProjectID ?? "default")-\(ServerSessionImport.scope(store.settings))")
        .sheet(item:$projectContext) { context in NavigationStack { ProjectSelector(chatID:context.id,settings:context.settings) } }
    }
}
private struct WorkspaceBrowser: View {
    let settings: ConnectionSettings
    let project: WorkspaceProject
    let chatTitle: String
    let choose: () -> Void
    @State private var path = ""
    @State private var listing: WorkspaceListing?
    @State private var error: String?
    @State private var busy = false
    @State private var importing = false
    @State private var selected: WorkspaceEntry?
    private let api = HermesAPI()
    var body: some View {
        List {
            Section {
                Button(action:choose) { Label("项目：\(project.name)",systemImage:"folder.badge.gearshape") }.accessibilityIdentifier("workspace-project-selector")
                Text("当前对话：\(chatTitle)").font(.caption)
                Text("App 专用文件工作区 · 不是终端 cwd").font(.headline)
                Text(listing?.scope ?? "专用工作区").font(.caption).textSelection(.enabled)
                Text("仅此目录内的非隐藏文档；不开放服务器主目录、配置或密钥。单文件 4 MB；不支持删除。上传同名文件会拒绝，不覆盖。") .font(.caption).foregroundStyle(.secondary)
            }
            Section { NavigationLink("关联 iPhone 文件夹 · 手动上传") { LinkedFolderView(settings:settings,projectID:project.id) } }
            if !path.isEmpty { Button("返回上层") { path = path.split(separator:"/").dropLast().joined(separator:"/"); Task { await reload() } } }
            if let error { Section { Text(error).foregroundStyle(.red); Button("重试") { Task { await reload() } } } }
            if busy { ProgressView("正在连接工作区…") }
            if let listing {
                Section(path.isEmpty ? "文件" : path) {
                    if listing.entries.isEmpty { Text("此目录没有可浏览的文档").foregroundStyle(.secondary) }
                    ForEach(listing.entries) { item in
                        Button {
                            if item.directory { path=item.path; Task { await reload() } }
                            else { selected=item }
                        } label: {
                            HStack {
                                Image(systemName:item.directory ? "folder" : item.name.lowercased().hasSuffix(".md") ? "doc.richtext" : ["png","jpg","jpeg","gif","webp","heic"].contains((item.name as NSString).pathExtension.lowercased()) ? "photo" : "doc.text")
                                    .foregroundStyle(.tint).frame(width:40,height:40).background(Color.accentColor.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
                                VStack(alignment:.leading,spacing:4) {
                                    Text(item.name).fixedSize(horizontal:false,vertical:true).foregroundStyle(.primary)
                                    if !item.directory { Text(ByteCountFormatter.string(fromByteCount:Int64(item.size),countStyle:.file)).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(); Image(systemName:"chevron.right").font(.caption)
                            }
                        }.disabled(busy)
                    }
                }
            }
        }.navigationTitle("文件").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { importing=true } label: { Label("上传",systemImage:"square.and.arrow.up") }.disabled(busy) }
        .refreshable { await reload() }.task { await reload() }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.plainText,.pdf,.image,.json,.commaSeparatedText],allowsMultipleSelection:false) { result in
            Task {
                do {
                    guard let url=try result.get().first else { return }
                    busy=true; defer { busy=false }
                    let data=try await LocalDocumentReader.read(url)
                    let target=path.isEmpty ? url.lastPathComponent : path+"/"+url.lastPathComponent
                    try await api.workspaceWrite(settings,path:target,data:data,etag:nil,projectID:project.id)
                    await reload()
                } catch { self.error=error.localizedDescription }
            }
        }
        .sheet(item:$selected,onDismiss:{ Task { await reload() } }) { item in
            NavigationStack { WorkspaceDocument(entry:item,settings:settings,projectID:project.id) }
        }
    }
    @MainActor private func reload() async {
        busy=true; defer { busy=false }
        do { listing=try await api.workspaceList(settings,path:path,projectID:project.id); error=nil }
        catch { self.error=error.localizedDescription; listing=nil }
    }
}

struct WorkspaceDocument: View {
    let entry: WorkspaceEntry
    let settings: ConnectionSettings
    var projectID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var directory: URL?
    @State private var etag: String?
    @State private var text = ""
    @State private var original = ""
    @State private var editing = false
    @State private var saving = false
    @State private var error: String?
    @State private var discard = false
    @State private var sharing = false
    private let api=HermesAPI()
    private var isText: Bool { ["txt","md","csv","json","log","yaml","yml"].contains((entry.name as NSString).pathExtension.lowercased()) }
    var body: some View {
        VStack(spacing:8) {
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(); Button("重新读取") { Task { await load() } }.disabled(editing) }
            if let localURL {
                if editing { TextEditor(text:$text).font(.system(.body,design:.monospaced)).accessibilityIdentifier("workspace-editor") }
                else if isText { ScrollView { if entry.name.lowercased().hasSuffix(".md") { MarkdownMessage(content:text).padding() } else { Text(text).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled).padding() } } }
                else if entry.name.lowercased().hasSuffix(".pdf") { PDFDocumentPreview(url:localURL) }
                else if let image=UIImage(contentsOfFile:localURL.path) { ScrollView([.horizontal,.vertical]) { Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:600) } }
                else { NativeDocumentPreview(url:localURL) }
                HStack {
                    Button { sharing=true } label: { Label("下载 / 分享",systemImage:"square.and.arrow.up") }.disabled(editing || saving)
                    Spacer()
                    if isText {
                        if editing {
                            Button("取消编辑") { text=original; editing=false }
                            Button("保存") { Task { await save() } }.disabled(saving || text==original)
                        } else { Button("编辑文本") { editing=true } }
                    }
                }.buttonStyle(.bordered).padding()
                if editing { Text("只在点击保存后写回服务器。发生版本冲突不会覆盖；取消后重新读取最新版本。").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
            } else if error == nil { ProgressView("下载预览…") }
        }.navigationTitle(entry.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("完成") { if editing && text != original { discard=true } else { dismiss() } } }
        .confirmationDialog("放弃未保存的编辑？",isPresented:$discard) { Button("放弃编辑",role:.destructive) { dismiss() }; Button("继续编辑",role:.cancel) {} }
        .sheet(isPresented:$sharing) {
            NavigationStack {
                if let localURL { WorkspaceShare(url:localURL).toolbar { Button("关闭分享") { sharing=false } } }
            }
        }
        .interactiveDismissDisabled(editing && text != original)
        .task { await load() }
        .onDisappear { if let directory { try? FileManager.default.removeItem(at:directory) } }
    }
    @MainActor private func load() async {
        do {
            let result=try await api.workspaceRead(settings,path:entry.path,projectID:projectID)
            if isText {
                guard let decoded=String(data:result.data,encoding:.utf8) else { throw ClientError.message("不是 UTF-8 文本，不能编辑。") }
                text=decoded; original=decoded
            }
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let url=folder.appendingPathComponent(URL(fileURLWithPath:entry.name).lastPathComponent)
            try result.data.write(to:url,options:[.atomic,.completeFileProtection])
            if let directory { try? FileManager.default.removeItem(at:directory) }
            directory=folder; localURL=url; etag=result.etag; error=nil
        } catch { self.error=error.localizedDescription }
    }
    @MainActor private func save() async {
        guard let etag else { return }; saving=true; defer { saving=false }
        do {
            try await api.workspaceWrite(settings,path:entry.path,data:Data(text.utf8),etag:etag,projectID:projectID)
            editing=false; await load()
        } catch { self.error=error.localizedDescription }
    }
}
struct PDFDocumentPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context:Context)->PDFView {
        let view=PDFView(); view.document=PDFDocument(url:url); view.autoScales=true
        view.accessibilityIdentifier="workspace-pdf"; return view
    }
    func updateUIView(_ view:PDFView,context:Context) {}
}
struct WorkspaceShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Return the native controller itself. Presenting another modal from a
        // host's viewDidAppear races SwiftUI's sheet transition and can be blank.
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
struct NativeDocumentPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context:Context) -> QLPreviewController {
        let controller=QLPreviewController(); controller.dataSource=context.coordinator; return controller
    }
    func updateUIViewController(_ controller:QLPreviewController,context:Context) {}
    final class Coordinator: NSObject,QLPreviewControllerDataSource {
        let url:URL
        init(_ url:URL) { self.url=url }
        func numberOfPreviewItems(in controller:QLPreviewController)->Int { 1 }
        func previewController(_ controller:QLPreviewController,previewItemAt index:Int)->QLPreviewItem { url as NSURL }
    }
}
#endif
