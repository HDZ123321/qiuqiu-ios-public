#if os(iOS)
import SwiftUI
import UIKit
#if SWIFT_PACKAGE
import HermesCore
#endif

@MainActor final class VoiceInputModel: ObservableObject {
    let session: VoiceInputSession
    private var lastPhase: VoiceInputSession.Phase = .idle
    convenience init() { self.init(driver: AppleVoiceInput()) }
    init(driver: VoiceInputDriver) {
        session = VoiceInputSession(driver: driver)
        session.changed = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            if self.lastPhase != self.session.phase {
                self.lastPhase = self.session.phase
                // Fixed numeric state only; no transcript, audio, locale or errors.
                let phases: [VoiceInputSession.Phase] = [.idle, .authorizing, .recording, .finishing, .preview, .failed, .cancelled]
                DiagnosticLog.shared.record(.voicePhase, code: phases.firstIndex(of: self.session.phase))
            }
        }
    }
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    func start() async {
        DiagnosticLog.shared.record(.voiceStart)
        await session.start(at: Self.now)
        session.recordingBegan(at: Self.now)
        if session.phase == .failed { DiagnosticLog.shared.record(.voiceUnavailable) }
    }
    func cancel() {
        if session.phase != .cancelled { DiagnosticLog.shared.record(.voiceCancel) }
        session.cancel()
    }
}

/// Text-input helper, not a voice conversation or audio-message transport.
@MainActor struct VoiceInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = VoiceInputModel()
    let insert: (String) -> Void
    private var session: VoiceInputSession { model.session }
    private var active: Bool { [.authorizing, .recording, .finishing].contains(session.phase) }
    var body: some View {
        NavigationStack {
            Form {
                Section("语音转文字 · 仅设备端") {
                    Text("使用 Apple Speech，仅允许设备端识别。最长 60 秒；不保存录音，不上传音频，不自动发送。不是语音通话或朗读。")
                        .font(.footnote)
                    Text("识别语言：\(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    switch session.phase {
                    case .idle:
                        Button { Task { await model.start() } } label: { Label("开始录音", systemImage: "mic.fill") }
                            .accessibilityIdentifier("voice-start")
                    case .authorizing:
                        ProgressView("等待麦克风与语音识别授权…")
                    case .recording:
                        Label("正在录音 · \(session.elapsed) / 60 秒", systemImage: "mic.fill")
                        Button("停止录音 · 预览文字") {
                            DiagnosticLog.shared.record(.voiceStop)
                            session.stop(at: VoiceInputModel.now)
                        }.accessibilityIdentifier("voice-stop")
                    case .finishing:
                        ProgressView("录音已停止，等待最终文字（最多 4 秒）…")
                    case .preview:
                        Text(session.transcript.isEmpty ? "未识别到文字，请返回键盘输入。" : "请检查、编辑后加入草稿。尚未发送。")
                    case .failed:
                        Text(failureMessage).foregroundStyle(.secondary)
                        if session.permission != .allowed {
                            Button("打开系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    case .cancelled:
                        Text("录音已取消；未保存或发送。请返回键盘输入。")
                    }
                }
                if session.phase != .cancelled {
                    Section("识别预览 · 可编辑") {
                        TextEditor(text: Binding(get: { session.transcript }, set: { session.transcript = String($0.prefix(16000)) }))
                            .frame(minHeight: 150).disabled(active)
                            .accessibilityLabel("语音转文字预览")
                            .accessibilityIdentifier("voice-preview")
                        Button("加入聊天草稿（不发送）") {
                            let text = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty, !active else { return }
                            insert(text)
                            DiagnosticLog.shared.record(.voiceDraftInserted)
                            model.cancel(); dismiss()
                        }.disabled(active || session.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("voice-insert")
                    }
                }
                Button("取消 · 返回键盘", role: .cancel) { model.cancel(); dismiss() }
                    .accessibilityIdentifier("voice-cancel")
            }
            .navigationTitle("语音输入").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { model.cancel(); dismiss() } } }
        }
        .interactiveDismissDisabled(active)
        .task {
            // Wall-clock polling avoids an unbounded recorder or finalization wait.
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { break }
                session.tick(at: VoiceInputModel.now)
            }
        }
        .onChange(of: scenePhase) { phase in
            // Permission prompts may temporarily make the scene inactive. Only
            // background cancels here; audio interruptions/route changes cancel
            // in the driver, including calls and unplugged microphones.
            if phase == .background { model.cancel() }
        }
        .onDisappear { model.cancel() }
    }
    private var failureMessage: String {
        switch session.permission {
        case .microphoneDenied: return "未获麦克风权限。可在系统设置中允许麦克风，或返回键盘输入。"
        case .speechDenied: return "未获语音识别权限（也可能受系统限制）。可在系统设置中检查，或返回键盘输入。"
        case .allowed:
            switch session.failure {
            case .unavailable: return "当前设备、系统语言或离线模型不支持设备端识别。不会回退到云端；请使用键盘。可检查系统语言与听写资源后重试。"
            case .audio: return "无法启动麦克风。请检查是否被其他应用占用，或返回键盘输入。"
            default: return "识别中断或失败，录音已停止。下方可能是未完成的文字，请检查编辑或返回键盘输入。"
            }
        }
    }
}
#endif
