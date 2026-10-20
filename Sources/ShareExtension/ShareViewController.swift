import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let host = UIHostingController(rootView: SharePreview(providers: providers, cancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }, complete: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
    }
}
private struct SharePreview: View {
    let providers: [NSItemProvider]
    let cancel: () -> Void
    let complete: () -> Void
    @State private var intake: ShareProviderIntake.Result?
    @State private var error: String?
    @State private var inbox: ShareInbox?
    @State private var loading = true
    @State private var saving = false
    @State private var saved = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("分享预览").font(.title2.bold())
                    Text("只保存到本机共享收件箱，不发送、不调用模型。保存后请手动打开球球，选择对话和项目并导入草稿，再手动发送。")
                    Text("最多 4 个附件，附件合计 4 MiB；文字最多 64 KiB。7 天后禁止导入，请重新分享。收件箱最多 16 项，需手动清理，不会自动丢弃旧内容。").font(.caption)
                }
                if loading { ProgressView("正在读取分享内容…") }
                if let intake {
                    if !intake.text.isEmpty { Section("文字 / 网页链接 · 外部数据") { Text(intake.text).textSelection(.enabled) } }
                    Section("附件") { ForEach(Array(intake.files.enumerated()), id: \.offset) { _, file in
                        VStack(alignment: .leading) { Text(file.name).fixedSize(horizontal: false, vertical: true); Text("\(file.data.count) 字节").font(.caption) }
                    } }
                }
                if let error { Section("未保存") { Text(error).foregroundStyle(.red).accessibilityIdentifier("share-error") } }
                if saved {
                    Section { Text("已保存到本机共享收件箱。请手动打开球球导入草稿；尚未发送。").accessibilityIdentifier("share-saved"); Button("完成", action: complete) }
                } else {
                    Section { Button("保存到球球") { save() }.accessibilityIdentifier("share-save").disabled(loading || saving || intake == nil || inbox == nil) }
                }
            }.navigationTitle("保存到球球").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !saved { Button("取消", action: cancel).disabled(saving) } }
            .task {
                // Still preview incoming data when signing lacks the shared group.
                do { inbox = try ShareContainer.open() } catch { self.error = error.localizedDescription }
                do { intake = try await ShareProviderIntake.load(providers) }
                catch { self.error = error.localizedDescription; intake = nil }
                loading = false
            }
        }.interactiveDismissDisabled(saving)
    }
    private func save() {
        guard let inbox, let intake, !saving, !saved else { return }
        saving = true
        do { _ = try inbox.save(text: intake.text, files: intake.files); saved = true; error = nil }
        catch { self.error = "保存失败，原内容未交接。请保留原内容后重试。\n"+error.localizedDescription }
        saving = false
    }
}
