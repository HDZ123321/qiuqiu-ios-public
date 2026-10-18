#if os(iOS)
import AVFoundation
import Speech
import Foundation
#if SWIFT_PACKAGE
import HermesCore
#endif

/// Injectable hardware boundary; notification policy remains in the real driver.
@MainActor protocol AppleVoiceCapture: AnyObject {
    var audioSession: AVAudioSession { get }
    func authorize() async -> VoicePermission
    func prepare(_ receive: @escaping (VoiceInputEvent) -> Void) throws
    func start() throws
    func finish()
    func cancel()
}

@MainActor final class AppleVoiceInput: VoiceInputDriver {
    private let capture: AppleVoiceCapture
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var observingInterruptions = false
    private var token = UUID()
    convenience init() { self.init(capture: LiveAppleVoiceCapture()) }
    init(capture: AppleVoiceCapture, notificationCenter: NotificationCenter = .default) {
        self.capture = capture; center = notificationCenter
    }
    func authorize() async -> VoicePermission { await capture.authorize() }
    func start(_ receive: @escaping (VoiceInputEvent) -> Void) throws {
        cancel()
        let generation = token
        do {
            try capture.prepare { [weak self] event in
                guard let self, self.token == generation else { return }
                receive(event)
            }
            observingInterruptions = true
            for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
                observers.append(center.addObserver(forName: name, object: capture.audioSession, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.token == generation, self.observingInterruptions else { return }
                        receive(.interrupted)
                    }
                })
            }
            try capture.start()
        } catch {
            cancel()
            throw error
        }
    }
    func finish() { detach(); capture.finish() }
    func cancel() { token = UUID(); detach(); capture.cancel() }
    private func detach() {
        observingInterruptions = false
        observers.forEach { center.removeObserver($0) }; observers.removeAll()
    }
}

/// Live PCM is passed only to an on-device-required Apple request. Never writes
/// an audio file, sends HTTP, logs samples/transcripts, or enables background audio.
@MainActor final class LiveAppleVoiceCapture: AppleVoiceCapture {
    let audioSession = AVAudioSession.sharedInstance()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var tapped = false
    private var audioActive = false
    private var token = UUID()
    func authorize() async -> VoicePermission {
        let generation = token
        let microphone = await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard microphone, generation == token else { return .microphoneDenied }
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return speech == .authorized ? .allowed : .speechDenied
    }
    func prepare(_ receive: @escaping (VoiceInputEvent) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: .current),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw VoiceInputFailure.unavailable }
        self.recognizer = recognizer
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true)
            audioActive = true
            let engine = AVAudioEngine(); self.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceInputFailure.audio }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request
            let generation = token
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.token == generation else { return }
                    if let text { receive(.transcript(text, final: final)) }
                    if failed && !final { receive(.failed(.recognition)) }
                }
            }
        } catch { cancel(); throw VoiceInputFailure.audio }
    }
    func start() throws { engine?.prepare(); try engine?.start() }
    func finish() { stopCapture(); request?.endAudio() }
    func cancel() {
        token = UUID(); stopCapture(); request?.endAudio()
        recognition?.cancel(); recognition = nil
        request = nil; recognizer = nil; engine = nil
    }
    private func stopCapture() {
        engine?.stop()
        if tapped { engine?.inputNode.removeTap(onBus: 0); tapped = false }
        if audioActive {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            audioActive = false
        }
    }
}
#endif
