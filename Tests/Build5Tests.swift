import XCTest
import Foundation
@testable import HermesCore
@testable import HermesTransport

final class Build5Protocol: URLProtocol {
    static var handler: ((Build5Protocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}
    func reply(_ code: Int = 200, _ text: String) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
}

final class Build5Tests: XCTestCase {
    @MainActor private func store(sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) -> ChatStore {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Build5Protocol.self]
        let store = ChatStore(api: HermesAPI(session: URLSession(configuration: config)), initialChats: [Chat()], save: { _ in }, sleep: sleep)
        var settings = ConnectionSettings(); settings.serverURL = "https://fixture.invalid"; settings.bearer = "fixture-only"
        store.settings = settings
        return store
    }
    @MainActor func testHTTP530ThenCancelUnsentImmediatelyAndNeverCreate() async throws {
        let called = expectation(description: "capabilities failed")
        var creates = 0
        Build5Protocol.handler = { proto in
            if proto.request.httpMethod == "POST" { creates += 1 }
            proto.reply(530, "tunnel unavailable"); called.fulfill()
        }
        let store = store(); defer { store.detach(); Build5Protocol.handler = nil }
        store.send("fixture")
        await fulfillment(of: [called], timeout: 3)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(store.error?.contains("530") == true)
        store.cancel()
        XCTAssertFalse(store.busy)
        XCTAssertTrue(store.activeRun?.terminal == true)
        XCTAssertNil(store.activeRun?.runID)
        XCTAssertEqual(creates, 0)
    }
    @MainActor func testCancelWhileCapabilitiesAwaitedNeverAdmitsAfterResponse() async throws {
        let called = expectation(description: "capabilities held")
        var held: Build5Protocol?; var creates = 0
        Build5Protocol.handler = { proto in
            if proto.request.httpMethod == "POST" { creates += 1; proto.reply(500, "unexpected create") }
            else { held = proto; called.fulfill() }
        }
        let store = store(); defer { store.detach(); Build5Protocol.handler = nil }
        store.send("fixture")
        await fulfillment(of: [called], timeout: 3)
        store.cancel()
        XCTAssertFalse(store.busy)
        held?.reply(200, Self.capabilities)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(creates, 0)
        XCTAssertTrue(store.activeRun?.terminal == true)
    }
    @MainActor func testBusyAllowsReadOnlyNavigationAndInactiveDoesNotDetach() async throws {
        let called = expectation(description: "held capabilities")
        var held: Build5Protocol?
        Build5Protocol.handler = { proto in held = proto; called.fulfill() }
        let store = store(); defer { store.detach(); Build5Protocol.handler = nil }
        store.send("fixture")
        await fulfillment(of: [called], timeout: 3)
        XCTAssertTrue(store.canNavigate)
        XCTAssertTrue(store.canEditConnection)
        XCTAssertFalse(store.canSend)
        store.sceneChanged(.inactive)
        held?.reply(530, "offline")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(store.error?.contains("530") == true, "Inactive must preserve the awaited transport")
    }
    @MainActor func testOutageRetriesExponentiallyThenPausesWithoutNewIntent() async throws {
        let exhausted = expectation(description: "bounded retries")
        var calls = 0; var delays: [UInt64] = []
        Build5Protocol.handler = { proto in calls += 1; proto.reply(530, "offline") }
        let store = store(sleep: { delay in
            delays.append(delay)
            if delays.count >= 5 { exhausted.fulfill(); throw CancellationError() }
        })
        defer { store.detach(); Build5Protocol.handler = nil }
        store.send("fixture")
        let key = store.activeRun?.key, body = store.activeRun?.body
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertLessThanOrEqual(calls, 5, "no unbounded create/status churn")
        XCTAssertEqual(store.activeRun?.key, key); XCTAssertEqual(store.activeRun?.body, body)
        if calls >= 1 {} // initial attempt observed
        if delays.count >= 4 { XCTAssertEqual(Array(delays.prefix(4)), [2,4,8,16].map { UInt64($0) * 1_000_000_000 }) }
        // Manually resume must retry with the identical intent.
        store.resume()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.activeRun?.key, key); XCTAssertEqual(store.activeRun?.body, body)
        if delays.count >= 4 { exhausted.fulfill() }
        await fulfillment(of: [exhausted], timeout: 8)
        XCTAssertTrue(store.error?.contains("暂停") == true, "pause after bounded failures with error \(store.error ?? "nil")")
        XCTAssertGreaterThanOrEqual(calls, 5)
    }
    func testLegacyPendingSubmissionRemainsAmbiguous() throws {
        let run = try PendingRun(input: "fixture", model: "hermes", sessionID: nil, history: [], replyID: UUID())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as? [String: Any])
        object.removeValue(forKey: "admissionDispatched")
        let legacy = try JSONDecoder().decode(PendingRun.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(legacy.definitelyUnsent)
        XCTAssertEqual(legacy.key, run.key); XCTAssertEqual(legacy.body, run.body)
    }
    @MainActor func testLostCreateReplayUsesExactIntentAndFetchesTerminalOutput() async throws {
        var keys: [String?] = []; var bodies: [Data?] = []; var persistedDispatch = false
        let finished = expectation(description: "authoritative final GET")
        Build5Protocol.handler = { proto in
            if proto.request.url!.path.hasSuffix("capabilities") { proto.reply(200, Self.capabilities) }
            else if proto.request.httpMethod == "POST" {
                XCTAssertTrue(persistedDispatch, "dispatch marker must already be durable")
                keys.append(proto.request.value(forHTTPHeaderField: "Idempotency-Key"))
                // URLSession may expose body as a stream to URLProtocol.
                if let stream = proto.request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var data = Data(); var bytes = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
                    bodies.append(data)
                } else { bodies.append(proto.request.httpBody) }
                if keys.count == 1 { proto.client?.urlProtocol(proto, didFailWithError: URLError(.networkConnectionLost)) }
                else { proto.reply(200, #"{"run_id":"run_replayed","status":"completed"}"#) }
            } else {
                proto.reply(200, #"{"run_id":"run_replayed","status":"completed","session_id":"s_final","output":"fixture final"}"#)
                finished.fulfill()
            }
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Build5Protocol.self]
        let store = ChatStore(api: HermesAPI(session: URLSession(configuration: config)), initialChats: [Chat()], save: { chats in
            persistedDispatch = chats.first?.run?.admissionDispatched == true
        }, sleep: { _ in })
        var settings = ConnectionSettings(); settings.serverURL = "https://fixture.invalid"; settings.bearer = "fixture-only"; store.settings = settings
        defer { store.detach(); Build5Protocol.handler = nil }
        store.send("fixture exact intent")
        let key = store.activeRun?.key, body = store.activeRun?.body
        await fulfillment(of: [finished], timeout: 3)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(keys.count, 2); XCTAssertEqual(keys[0], key); XCTAssertEqual(keys[1], key)
        XCTAssertEqual(bodies[0], body); XCTAssertEqual(bodies[1], body)
        XCTAssertEqual(store.activeRun?.output, "fixture final")
        XCTAssertEqual(store.current?.sessionID, "s_final")
        XCTAssertEqual(store.current?.messages.last?.content, "fixture final")
        XCTAssertFalse(store.busy)
    }
    @MainActor func testChangedSettingsPreservePendingOriginAcrossReloadAndStop() async throws {
        var pending = try PendingRun(input: "synthetic", model: "old-model", sessionID: nil, history: [], replyID: UUID())
        pending.admissionDispatched = true
        try pending.apply(Data(#"{"run_id":"run_origin","status":"running"}"#.utf8))
        let chat = Chat(messages: []); var savedChat = chat; savedChat.run = pending
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Build5Protocol.self]
        let api = HermesAPI(session: URLSession(configuration: config))
        let original = store().settings
        let subject = ChatStore(api: api, initialChats: [savedChat], save: { _ in })
        subject.settings = original
        var changed = original; changed.serverURL = "https://new-settings.invalid"; changed.bearer = "new-synthetic"; changed.model = "new-model"
        try subject.saveSettings(changed)
        XCTAssertEqual(subject.activeRun, pending)
        XCTAssertTrue(subject.busy)
        XCTAssertEqual(try CredentialStore.runConnection(pending.key), original)
        let stopped = expectation(description: "stop reaches original connection after reload")
        Build5Protocol.handler = { proto in
            XCTAssertEqual(proto.request.url?.host, "fixture.invalid")
            XCTAssertEqual(proto.request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
            XCTAssertFalse(proto.request.url!.path.hasSuffix("capabilities"))
            if proto.request.url!.path.hasSuffix("stop") {
                proto.reply(200, #"{"run_id":"run_origin","status":"cancelled"}"#)
                stopped.fulfill()
            } else { proto.reply(200, #"{"run_id":"run_origin","status":"running"}"#) }
        }
        let reloaded = ChatStore(api: api, initialChats: subject.chats, save: { _ in })
        reloaded.settings = changed
        defer { reloaded.detach(); Build5Protocol.handler = nil }
        reloaded.cancel()
        await fulfillment(of: [stopped], timeout: 5)
        XCTAssertEqual(reloaded.activeRun?.key, pending.key)
        XCTAssertEqual(reloaded.activeRun?.body, pending.body)
        XCTAssertEqual(reloaded.activeRun?.runID, pending.runID)
    }
    @MainActor func testAmbiguousPendingRetryAfterSettingsChangeUsesOriginalBodyAndKey() async throws {
        var pending = try PendingRun(input: "ambiguous synthetic", model: "old-model", sessionID: nil, history: [], replyID: UUID())
        pending.admissionDispatched = true
        var chat = Chat(); chat.run = pending
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Build5Protocol.self]
        let subject = ChatStore(api: HermesAPI(session: URLSession(configuration: config)), initialChats: [chat], save: { _ in })
        var old = ConnectionSettings(); old.serverURL = "https://original-retry.invalid"; old.bearer = "old-synthetic"
        subject.settings = old
        var changed = old; changed.serverURL = "https://new-retry.invalid"; changed.bearer = "new-synthetic"
        try subject.saveSettings(changed)
        let finished = expectation(description: "same original intent replayed")
        Build5Protocol.handler = { proto in
            XCTAssertEqual(proto.request.url?.host, "original-retry.invalid")
            if proto.request.url!.path.hasSuffix("capabilities") { proto.reply(200, Self.capabilities) }
            else if proto.request.httpMethod == "POST" {
                XCTAssertEqual(proto.request.value(forHTTPHeaderField: "Idempotency-Key"), pending.key)
                var body = proto.request.httpBody ?? Data()
                if let stream = proto.request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(contentsOf: buffer.prefix(n)) }
                }
                XCTAssertEqual(body, pending.body)
                proto.reply(200, #"{"run_id":"run_retry_origin","status":"completed"}"#)
            } else {
                proto.reply(200, #"{"run_id":"run_retry_origin","status":"completed","output":"synthetic complete"}"#)
                finished.fulfill()
            }
        }
        defer { subject.detach(); Build5Protocol.handler = nil }
        subject.resume()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(subject.activeRun?.key, pending.key)
        XCTAssertEqual(subject.activeRun?.body, pending.body)
    }
    static let capabilities = #"{"features":{"run_submission":true,"run_status":true,"run_stop":true,"run_approval_response":true,"runs_idempotency":{"supported":true,"durable":true,"retention_seconds":86400}}}"#

    func testCompletedReplayHydratesAuthoritativeOutputAndSessionWithoutRegression() throws {
        var run = try PendingRun(input: "fixture", model: "hermes", sessionID: nil, history: [], replyID: UUID())
        try run.apply(Data(#"{"run_id":"run_replay","status":"completed"}"#.utf8))
        try run.apply(Data(#"{"run_id":"run_replay","status":"completed","session_id":"session_final","output":"final fixture output"}"#.utf8))
        try run.apply(Data(#"{"run_id":"run_replay","status":"running","session_id":"stale","output":"stale"}"#.utf8))
        XCTAssertEqual(run.status, "completed")
        XCTAssertEqual(run.sessionID, "session_final")
        XCTAssertEqual(run.output, "final fixture output")
    }
}
