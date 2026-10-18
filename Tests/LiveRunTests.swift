import XCTest
import Foundation
import HermesCore
@testable import HermesTransport

final class LiveRunTests: XCTestCase {
    @MainActor func testProductionChatStoreSendDetachRecoverAndExplicitStop() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["QIU_LIVE_BASE"], !base.isEmpty, let key = env["QIU_LIVE_KEY"], !key.isEmpty else {
            throw XCTSkip("Production credentials absent; live behavior NOT verified")
        }
        let store = ChatStore()
        store.detach()
        store.chats = [Chat()]; store.selected = store.chats[0].id; store.busy = false
        var settings = ConnectionSettings(); settings.serverURL = base; settings.bearer = key; settings.model = "hermes-agent"
        store.settings = settings
        store.send("Connectivity regression only. No tools or memory writes. Reply exactly BUILD4_OK_中文.")
        // Exercise the actual App path, including its URLSession SSE subscriber.
        for _ in 0..<200 {
            if store.activeRun?.runID != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNotNil(store.activeRun?.runID)
        let admitted = store.activeRun?.runID
        try await Task.sleep(nanoseconds: 300_000_000)
        store.detach()
        XCTAssertFalse(store.activeRun?.stopRequested ?? true)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        store.resume()
        for _ in 0..<120 {
            if store.activeRun?.terminal == true { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTAssertEqual(store.activeRun?.runID, admitted)
        XCTAssertEqual(store.activeRun?.status, "completed")
        XCTAssertTrue(store.activeRun?.output?.contains("BUILD4_OK") == true)
        XCTAssertFalse(store.busy)
        // Continuation uses the real server-generated session, not transcript replacement.
        store.send("Connectivity regression only. No tools or memory writes. Reply exactly FOLLOWUP_OK.")
        for _ in 0..<200 {
            if store.activeRun?.runID != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNotNil(store.activeRun?.runID)
        store.cancel() // Simulates the separately confirmed destructive action only.
        for _ in 0..<60 {
            if store.activeRun?.terminal == true { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTAssertTrue(["cancelled", "completed"].contains(store.activeRun?.status ?? ""))
        let exported = try String(contentsOf: DiagnosticLog.shared.export())
        XCTAssertTrue(exported.contains(" stopIntent "))
        XCTAssertTrue(exported.contains("route=stop"))
        XCTAssertTrue(exported.contains(" detach "))
        XCTAssertTrue(exported.contains("state=completed"))
        XCTAssertFalse(exported.contains(key))
        XCTAssertFalse(exported.contains("Connectivity regression only"))
        store.detach()
        print("LIVE_APP_PATH: send/admission/SSE/detach/recover/final/session-followup/explicit-stop verified")
    }
}
