import XCTest
import AVFoundation
@testable import QiuQiu

/// Replays synthetic notification order only. No microphone, Speech, PCM or
/// user diagnostics are needed; the actual AppleVoiceInput observer is exercised.
@MainActor final class AppleVoiceNotificationTests: XCTestCase {
    func testOwnActivationRouteNotificationDoesNotCancelRecording() async {
        let center = NotificationCenter()
        let capture = NotificationCapture(center: center)
        capture.activationReason = .categoryChange
        let driver = AppleVoiceInput(capture: capture, notificationCenter: center)
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        await settle()
        XCTAssertEqual(session.phase, .recording, "Our own setCategory/activation route event must not cancel a successful start")
        session.cancel()
    }
    func testOldDeviceUnavailableCancelsAndReleasesCapture() async {
        let center = NotificationCenter()
        let capture = NotificationCapture(center: center)
        let driver = AppleVoiceInput(capture: capture, notificationCenter: center)
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        capture.post(.oldDeviceUnavailable)
        await settle()
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertGreaterThan(capture.cancelCount, 0)
    }
    func testInterruptionEndedDoesNotCancelRecording() async {
        let center = NotificationCenter()
        let capture = NotificationCapture(center: center)
        let driver = AppleVoiceInput(capture: capture, notificationCenter: center)
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        center.post(name: AVAudioSession.interruptionNotification, object: capture.audioSession,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        await settle()
        XCTAssertEqual(session.phase, .recording)
        session.cancel()
    }
    func testInterruptionBeganCancelsRecording() async {
        let center = NotificationCenter()
        let capture = NotificationCapture(center: center)
        let driver = AppleVoiceInput(capture: capture, notificationCenter: center)
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        center.post(name: AVAudioSession.interruptionNotification, object: capture.audioSession,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        await settle()
        XCTAssertEqual(session.phase, .cancelled)
    }
    func testQueuedOldGenerationCannotCancelNewRecording() async throws {
        let center = NotificationCenter()
        let capture = NotificationCapture(center: center)
        let driver = AppleVoiceInput(capture: capture, notificationCenter: center)
        var old = 0; var current = 0
        try driver.start { _ in old += 1 }
        capture.post(.oldDeviceUnavailable) // observer queues a main-actor delivery
        driver.cancel()
        try driver.start { _ in current += 1 }
        await settle()
        XCTAssertEqual(old, 0); XCTAssertEqual(current, 0)
        driver.cancel()
    }
    func testFinishDetachesBeforeOwnDeactivationRouteEvent() async {
        let center = NotificationCenter()
        let capture = NotificationCapture(center: center)
        let driver = AppleVoiceInput(capture: capture, notificationCenter: center)
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        session.stop(at: 1)
        await settle()
        XCTAssertEqual(session.phase, .finishing)
        session.tick(at: 5)
        XCTAssertEqual(session.phase, .preview)
    }
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}

@MainActor private final class NotificationCapture: AppleVoiceCapture {
    let center: NotificationCenter
    let audioSession = AVAudioSession.sharedInstance()
    var activationReason: AVAudioSession.RouteChangeReason?
    var cancelCount = 0
    init(center: NotificationCenter) { self.center = center }
    func authorize() async -> VoicePermission { .allowed }
    func prepare(_ receive: @escaping (VoiceInputEvent) -> Void) throws {
        // The live prepare uses setCategory/setActive. iOS delivers its route
        // event asynchronously after observers are installed and start returns.
        if let activationReason {
            DispatchQueue.main.async { [self] in post(activationReason) }
        }
    }
    func start() throws {}
    func finish() { post(.categoryChange) }
    func cancel() { cancelCount += 1 }
    func post(_ reason: AVAudioSession.RouteChangeReason) {
        center.post(name: AVAudioSession.routeChangeNotification, object: audioSession,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }
}
