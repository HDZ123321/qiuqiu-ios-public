#if os(iOS)
import SwiftUI
import UIKit
#if SWIFT_PACKAGE
import HermesCore
#endif

@MainActor final class VoiceInputModel: ObservableObject {
    @Published private(set) var session: VoiceInputSession
    private var lastPhase: VoiceInputSession.Phase = .idle
    convenience init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-inline-voice") { self.init(driver: SyntheticInlineVoice()); return }
        #endif
        self.init(driver: AppleVoiceInput())
    }
    init(driver: VoiceInputDriver) { session = VoiceInputSession(driver: driver); observe() }
    private func observe() {
        session.changed = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            if self.lastPhase != self.session.phase {
                self.lastPhase = self.session.phase
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
    }
    func cancel(source: Int = 10) {
        DiagnosticLog.shared.record(.voiceCancellation, frames: source, code: 0)
        session.cancel()
    }
    var statusText: String {
        switch session.phase {
        case .idle: return ""
        case .authorizing: return "等待麦克风与语音识别授权…"
        case .recording: return "正在录音 · 仅设备端 · \(session.elapsed)/60 秒 · 不保存音频，不自动发送"
        case .finishing: return "录音已停止，等待最终文字（最多 4 秒）…"
        case .preview: return session.transcript.isEmpty ? "未识别到文字，请使用键盘。" : "语音已转为草稿，可编辑后手动发送。"
        case .cancelled: return "录音已取消，草稿未发送。"
        case .failed:
            if session.permission == .microphoneDenied { return "未获麦克风权限，请在系统设置中允许或使用键盘。" }
            if session.permission == .speechDenied { return "未获语音识别权限，请在系统设置中允许或使用键盘。" }
            if session.failure == .unavailable { return "此设备或语言不支持设备端识别；不会回退云端，请使用键盘。" }
            return "语音识别失败，录音已停止；请检查草稿或使用键盘。"
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic permission/audio seam only. Never included in an iPhoneOS build.
@MainActor private final class SyntheticInlineVoice: VoiceInputDriver {
    var receive: ((VoiceInputEvent) -> Void)?
    var task: Task<Void, Never>?
    func authorize() async -> VoicePermission {
        if ProcessInfo.processInfo.arguments.contains("--ui-voice-denied") { return .microphoneDenied }
        return .allowed
    }
    func start(_ receive: @escaping (VoiceInputEvent) -> Void) throws {
        self.receive = receive
        task = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }; receive(.transcript("synthetic", final: false))
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }; receive(.transcript("synthetic words", final: false))
            if ProcessInfo.processInfo.arguments.contains("--ui-voice-error") { receive(.failed(.recognition)) }
        }
    }
    func finish() { receive?(.transcript("synthetic words final", final: true)) }
    func cancel() { task?.cancel(); task = nil; receive = nil }
}
#endif
#endif
