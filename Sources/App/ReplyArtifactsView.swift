#if os(iOS)
import SwiftUI
import UIKit

struct ReplyArtifactsView: View {
    let runID: String
    let settings: ConnectionSettings
    @State private var items: [ReplyArtifact] = []
    @State private var error: String?
    private let api = HermesAPI()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            ForEach(items) { item in ReplyArtifactCard(item: item, runID: runID, settings: settings) }
        }.task(id: runID + settings.serverURL) {
            do { items = try await api.replyArtifacts(settings, runID: runID); error = items.isEmpty ? "文件未在专用工作区内；不读取服务器私有路径。" : nil }
            catch { self.error = "回复产物接口未开放或连接失败；不会读取任意服务器路径。" }
        }
    }
}

struct ReplyArtifactCard: View {
    let item: ReplyArtifact
    let runID: String
    let settings: ConnectionSettings
    @State private var data: Data?
    @State private var localURL: URL?
    @State private var folder: URL?
    @State private var preview = false
    @State private var sharing = false
    @State private var error: String?
    @State private var busy = false
    private let api = HermesAPI()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data, item.image, let image = UIImage(data: data) {
                Button { preview = true } label: { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220) }
                    .accessibilityLabel("预览图片 " + item.name).accessibilityIdentifier("reply-image")
            }
            Text(item.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(item.mime).font(.caption).foregroundStyle(.secondary)
            Text(data.map { ByteCountFormatter.string(fromByteCount: Int64($0.count), countStyle: .file) } ?? "大小在下载后核实 · 上限 4 MB").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Button { Task { await download(); if localURL != nil { preview = true } } } label: {
                Label(busy ? "下载中…" : "预览文件", systemImage: item.image ? "photo" : "doc.text")
            }.buttonStyle(.bordered).disabled(busy).accessibilityIdentifier("reply-file-preview")
        }.task { if item.image { await download() } }
        .sheet(isPresented: $preview) {
            NavigationStack {
                if let localURL {
                    VStack {
                        if item.image, let data, let image = UIImage(data: data) { ScrollView([.horizontal,.vertical]) { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 800) }.accessibilityIdentifier("reply-image-preview") }
                        else if item.mime == "application/pdf" { PDFDocumentPreview(url: localURL) }
                        else if let data, let text = String(data: data, encoding: .utf8) { ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }.accessibilityIdentifier("reply-file-content") }
                        else { NativeDocumentPreview(url: localURL) }
                        Button { sharing = true } label: { Label("下载 / 分享产物", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered).padding()
                    }.navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("关闭预览") { preview = false } }
                    .sheet(isPresented: $sharing) { NavigationStack { WorkspaceShare(url: localURL).toolbar { Button("关闭分享") { sharing = false } } } }
                }
            }
        }
        .onDisappear { if let folder { try? FileManager.default.removeItem(at: folder) }; localURL = nil }
    }
    @MainActor private func download() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let bytes = try await api.replyArtifact(settings, runID: runID, artifact: item)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(item.name)
            try bytes.write(to: url, options: [.atomic, .completeFileProtection])
            if let folder { try? FileManager.default.removeItem(at: folder) }
            folder = dir; localURL = url; data = bytes; error = nil
        } catch { self.error = "产物下载失败，请重试；不会转向外部地址。" }
    }
}
#endif
