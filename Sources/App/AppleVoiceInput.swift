#if os(iOS)
import AVFoundation
import Speech
import Foundation
#if SWIFT_PACKAGE
import HermesCore
#endif

/// Live PCM is passed only to an on-device-required Apple request. Never writes
/// an audio file, sends HTTP, logs samples/transcripts, or enables background audio.
@MainActor final class AppleVoiceInput: VoiceInputDriver {
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var observers: [NSObjectProtocol] = []
    private var tapped = false
    private var audioActive = false
    private var observingInterruptions = false
    private var receive: ((VoiceInputEvent) -> Void)?
    private var token = UUID()

    func authorize() async -> VoicePermission {
        let generation = token
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard microphone, generation == token else { return .microphoneDenied }
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return speech == .authorized ? .allowed : .speechDenied
    }
    func start(_ receive: @escaping (VoiceInputEvent) -> Void) throws {
        cancel()
        guard let recognizer = SFSpeechRecognizer(locale: .current),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw VoiceInputFailure.unavailable
        }
        self.recognizer = recognizer
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audio.setActive(true)
            audioActive = true
            let engine = AVAudioEngine()
            self.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceInputFailure.audio }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request
            self.receive = receive
            let generation = token
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                // Audio thread: do not touch actor/UI state or copy PCM into logs.
                request.append(buffer)
            }
            tapped = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.token == generation else { return }
                    if let text { self.receive?(.transcript(text, final: final)) }
                    if failed && !final { self.receive?(.failed(.recognition)) }
                }
            }
            observingInterruptions = true
            for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: audio, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.token == generation, self.observingInterruptions else { return }
                        self.receive?(.interrupted)
                    }
                })
            }
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw VoiceInputFailure.audio
        }
    }
    func finish() {
        // Deactivation can itself emit route-change notifications. Detach these
        // before intentional shutdown so Stop does not discard the preview.
        observingInterruptions = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        stopCapture()
        request?.endAudio()
        // Keep the recognition task for a bounded final result (core: 4 seconds).
    }
    func cancel() {
        token = UUID()
        receive = nil
        observingInterruptions = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        stopCapture()
        request?.endAudio()
        recognition?.cancel(); recognition = nil
        request = nil; recognizer = nil; engine = nil
    }
    private func stopCapture() {
        engine?.stop()
        if tapped { engine?.inputNode.removeTap(onBus: 0); tapped = false }
        if audioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioActive = false
        }
    }
}
#endif
