#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct LinkedFolderView: View {
    @EnvironmentObject private var store: ChatStore
    @AppStorage("qiu.linkedFolder") private var bookmark = Data()
    @State private var picking = false
    @State private var entries: [URL] = []
    @State private var root: URL?
    @State private var error: String?
    @State private var busy = false
    @State private var result: String?
    private let api = HermesAPI()
    var body: some View {
        List {
            Section {
                Text("关联 iPhone 文件夹").font(.headline)
                Text("仅访问你在系统“文件”中明确选择的文件夹。不是服务器挂载；不会自动扫描子目录或后台同步。逐个点击文件才上传，服务器同名文件不覆盖。") .font(.caption)
                Button("选择 / 更换文件夹") { picking = true }.disabled(busy)
                if !bookmark.isEmpty { Button("取消关联",role:.destructive) { bookmark=Data(); root=nil; entries=[] } }
            }
            if let error { Text(error).foregroundStyle(.red) }
            if let result { Text(result).font(.caption) }
            if busy { ProgressView("读取或上传中…") }
            if let root { Text(root.lastPathComponent).font(.headline); Button("刷新文件列表") { load() }.disabled(busy) }
            ForEach(entries,id:\.self) { url in
                Button { upload(url) } label: { Label(url.lastPathComponent,systemImage:"square.and.arrow.up") }.disabled(busy)
            }
        }.navigationTitle("关联文件夹")
        .fileImporter(isPresented:$picking,allowedContentTypes:[.folder],allowsMultipleSelection:false) { selection in
            do {
                guard let url=try selection.get().first else { return }
                let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                bookmark=try url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil)
                load()
            } catch { self.error="关联失败（代码 \((error as NSError).code)）；请重新选择文件夹。" }
        }.task { load() }
    }
    private func resolve() throws -> URL {
        var stale=false
        let url=try URL(resolvingBookmarkData:bookmark,options:.withoutUI,relativeTo:nil,bookmarkDataIsStale:&stale)
        guard !stale else { throw ClientError.message("授权已过期，请重新选择文件夹。") }
        return url
    }
    private func load() {
        guard !bookmark.isEmpty else { return }
        do {
            let url=try resolve(); let access=url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let items=try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:.skipsHiddenFiles)
            guard items.count<=1000 else { throw ClientError.message("此文件夹超过 1000 项，请选择较小的文件夹。") }
            entries=try items.filter { item in
                let values=try item.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                return values.isRegularFile == true && values.isSymbolicLink != true && ["txt","md","csv","json","log","yaml","yml","pdf","png","jpg","jpeg","gif","webp","heic"].contains(item.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            root=url; error=nil
        } catch { self.error="无法读取关联文件夹（代码 \((error as NSError).code)）。授权可能失效；请重新选择。"; entries=[] }
    }
    private func upload(_ url: URL) {
        busy=true; error=nil; result=nil
        Task { @MainActor in
            defer { busy=false }
            do {
                let folder=try resolve(); let access=folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                guard url.deletingLastPathComponent()==folder else { throw ClientError.message("文件不在授权文件夹内。") }
                let data=try await LocalDocumentReader.read(url)
                try await api.workspaceWrite(store.settings,path:url.lastPathComponent,data:data,etag:nil)
                let check=try await api.workspaceRead(store.settings,path:url.lastPathComponent)
                guard check.data==data else { throw ClientError.message("服务器回读不一致。") }
                result="上传并回读核实：\(url.lastPathComponent)"
            } catch let failure as HTTPFailure where failure.status==409 {
                self.error="服务器已存在同名文件；未覆盖。请先重命名本地文件。"
            } catch { self.error="上传失败（代码 \((error as NSError).code)）；文件保留在本机，可重试。" }
        }
    }
}
#endif
