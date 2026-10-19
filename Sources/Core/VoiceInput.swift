import Foundation

public enum VoicePermission: Equatable { case allowed, microphoneDenied, speechDenied }
public enum VoiceInputFailure: Error, Equatable { case unavailable, audio, recognition }
public enum VoiceInputEvent { case transcript(String, final: Bool), failed(VoiceInputFailure), interrupted }

/// The Apple adapter and tests share this exact boundary. No file or network API.
@MainActor public protocol VoiceInputDriver: AnyObject {
    func authorize() async -> VoicePermission
    func start(_ receive: @escaping (VoiceInputEvent) -> Void) throws
    func finish()
    func cancel()
}

/// A single sheet owns one session. Transcript remains volatile until the user
/// explicitly inserts it into the normal composer; this type cannot send a run.
@MainActor public final class VoiceInputSession {
    public enum Phase: Equatable { case idle, authorizing, recording, finishing, preview, failed, cancelled }
    public private(set) var phase: Phase = .idle
    public var transcript = "" { didSet { changed?() } }
    public private(set) var permission: VoicePermission = .allowed
    public private(set) var failure: VoiceInputFailure?
    public private(set) var elapsed = 0
    public var changed: (() -> Void)?
    public static let maximumDuration: TimeInterval = 60
    public static let finalizationDuration: TimeInterval = 4
    private let driver: VoiceInputDriver
    private var generation = UUID()
    private var startedAt: TimeInterval = 0
    private var stoppedAt: TimeInterval = 0
    private var ownsDriver = false
    public init(driver: VoiceInputDriver) { self.driver = driver }

    public func start(at now: TimeInterval) async {
        guard ![.authorizing, .recording, .finishing].contains(phase) else { return }
        transcript = ""; permission = .allowed; failure = nil; elapsed = 0
        generation = UUID()
        let token = generation
        phase = .authorizing; ownsDriver = true; changed?()
        let result = await driver.authorize()
        guard token == generation, phase == .authorizing else { return }
        permission = result
        guard result == .allowed else { phase = .failed; releaseDriver(); changed?(); return }
        // The caller's clock may advance during the system permission dialogs.
        // Capture time is set by the first timer tick, not time spent authorizing.
        startedAt = now; elapsed = 0; phase = .recording
        ownsDriver = true
        do {
            try driver.start { [weak self] event in
                guard let self, self.generation == token else { return }
                self.receive(event)
            }
        } catch {
            failure = (error as? VoiceInputFailure) ?? .audio
            phase = .failed; releaseDriver()
        }
        changed?()
    }
    /// Rebase after permission dialogs so they cannot consume the recording cap.
    public func recordingBegan(at now: TimeInterval) {
        guard phase == .recording else { return }
        startedAt = now
    }
    public func tick(at now: TimeInterval) {
        if phase == .recording {
            elapsed = max(0, Int(now - startedAt))
            if now - startedAt >= Self.maximumDuration { stop(at: now) }
            else { changed?() }
        } else if phase == .finishing, now - stoppedAt >= Self.finalizationDuration {
            complete()
        }
    }
    public func stop(at now: TimeInterval) {
        guard phase == .recording else { return }
        phase = .finishing; stoppedAt = now
        driver.finish(); changed?()
    }
    public func cancel() {
        generation = UUID() // invalidate late permissions, results and errors
        releaseDriver(); phase = .cancelled; transcript = ""; changed?()
    }
    private func receive(_ event: VoiceInputEvent) {
        guard phase == .recording || phase == .finishing else { return }
        switch event {
        case let .transcript(text, final):
            transcript = String(text.prefix(16000))
            if final { complete() }
        case let .failed(error):
            failure = error; phase = .failed; releaseDriver(); changed?()
        case .interrupted:
            cancel()
        }
    }
    private func complete() {
        phase = .preview; releaseDriver(); changed?()
    }
    private func releaseDriver() {
        guard ownsDriver else { return }
        ownsDriver = false; driver.cancel()
    }
}
