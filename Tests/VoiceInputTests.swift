import XCTest
@testable import HermesCore

@MainActor final class VoiceInputTests: XCTestCase {
    func testStartNeedsPermissionsAndNeverCommitsAutomatically() async {
        let driver = VoiceFake()
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        XCTAssertEqual(session.phase, .recording)
        driver.emit?(.transcript("hello", final: true))
        XCTAssertEqual(session.phase, .preview)
        XCTAssertEqual(session.transcript, "hello")
        XCTAssertEqual(driver.cleanups, 1)
    }
    func testDeniedPermissionNeverStartsAudio() async {
        let driver = VoiceFake(); driver.permission = .microphoneDenied
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.permission, .microphoneDenied)
        XCTAssertNil(driver.emit)
    }
    func testUnavailableOnDeviceFallsBackWithoutAudio() async {
        let driver = VoiceFake(); driver.supported = false
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        XCTAssertEqual(session.failure, .unavailable)
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(driver.cleanups, 1)
    }
    func testTimeoutEndsCaptureThenBoundsFinalization() async {
        let driver = VoiceFake(); let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        session.recordingBegan(at: 100)
        session.tick(at: 159)
        XCTAssertEqual(session.phase, .recording)
        session.tick(at: 160)
        XCTAssertEqual(session.phase, .finishing)
        XCTAssertEqual(driver.finishes, 1)
        session.tick(at: 164)
        XCTAssertEqual(session.phase, .preview)
        XCTAssertEqual(driver.cleanups, 1)
    }
    func testCancelDiscardsAndRejectsLateResults() async {
        let driver = VoiceFake(); let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        driver.emit?(.transcript("private", final: false))
        session.cancel(); driver.emit?(.transcript("late", final: true))
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertEqual(session.transcript, "")
        XCTAssertEqual(driver.cleanups, 1)
    }
    func testErrorAllowsExplicitPartialPreviewButDoesNotCommit() async {
        let driver = VoiceFake(); let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        driver.emit?(.transcript("partial", final: false))
        driver.emit?(.failed(.recognition))
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.transcript, "partial")
        XCTAssertEqual(driver.cleanups, 1)
    }
    func testCancelWhilePermissionPendingCannotStartCapture() async {
        let driver = VoiceFake(); driver.delayPermission = true
        let session = VoiceInputSession(driver: driver)
        let pending = Task { await session.start(at: 0) }
        while driver.permissionContinuation == nil { await Task.yield() }
        session.cancel()
        driver.permissionContinuation?.resume(returning: .allowed)
        await pending.value
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertNil(driver.emit)
    }
    func testSpeechDeniedNeverStartsAudio() async {
        let driver = VoiceFake(); driver.permission = .speechDenied
        let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        XCTAssertEqual(session.permission, .speechDenied)
        XCTAssertEqual(session.phase, .failed)
        XCTAssertNil(driver.emit)
    }
    func testRepeatedStopAndCancelAreIdempotent() async {
        let driver = VoiceFake(); let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        session.stop(at: 1); session.stop(at: 2)
        session.cancel(); session.cancel()
        XCTAssertEqual(driver.finishes, 1)
        XCTAssertEqual(driver.cleanups, 1)
    }
    func testRouteInterruptionDiscardsDraft() async {
        let driver = VoiceFake(); let session = VoiceInputSession(driver: driver)
        await session.start(at: 0)
        driver.emit?(.interrupted)
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertEqual(driver.cleanups, 1)
    }
}

@MainActor private final class VoiceFake: VoiceInputDriver {
    var permission: VoicePermission = .allowed
    var supported = true
    var emit: ((VoiceInputEvent) -> Void)?
    var cleanups = 0
    var finishes = 0
    var delayPermission = false
    var permissionContinuation: CheckedContinuation<VoicePermission, Never>?
    func authorize() async -> VoicePermission {
        if delayPermission { return await withCheckedContinuation { permissionContinuation = $0 } }
        return permission
    }
    func start(_ receive: @escaping (VoiceInputEvent) -> Void) throws {
        guard supported else { throw VoiceInputFailure.unavailable }
        emit = receive
    }
    func finish() { finishes += 1 }
    func cancel() { cleanups += 1 }
}
