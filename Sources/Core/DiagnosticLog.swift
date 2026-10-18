import Foundation

// Typed events and numeric fields only: never accept arbitrary diagnostic text.
public final class DiagnosticLog: @unchecked Sendable {
    public enum Event: String { case app, voiceAudioEvent, voiceCancellation, voiceStart, voicePhase, voiceStop, voiceCancel, voiceUnavailable, voiceDraftInserted, pickerPhotoOpen, pickerDocumentOpen, importCancelled, providerError, attachmentRejected, attachmentValidated, attachmentAdded, photoSelected, photoRead, photoNormalized, importSelected, importRead, importFailed, uploadStart, uploadVerified, uploadFailed, abandonedUnsent, admissionDispatched, retryPaused, retryScheduled, inactiveScene, requestStart, response, firstToken, done, cancel, error, foreground, background, auth, probe, send, detach, resume, stopPrompt, stopDismissed, stopIntent, stopSent, runState, pollFallback, approvalSeen, approvalOnce, approvalDeny, toolStarted, toolCompleted, streamEnd }
    public enum Route: String { case capabilities, create, status, events, stop, approval, sessionList, sessionMessages, other }
    public enum State: String { case creating, queued, started, running, waiting_for_approval, stopping, completed, failed, cancelled, interrupted, unknown }
    public static func route(_ path: String) -> Route {
        if path == "capabilities" { return .capabilities }
        if path == "runs" { return .create }
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "runs" else { return .other }
        if parts.count == 2 { return .status }
        return ["events": .events, "stop": .stop, "approval": .approval][String(parts[2])] ?? .other
    }
    public static let shared = DiagnosticLog(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics"))
    private let directory: URL
    private let limit: Int
    private let lock = NSLock()
    public init(directory: URL, limit: Int = 65536) { self.directory = directory; self.limit = max(512, limit) }
    public func record(_ event: Event, id: UUID? = nil, url: URL? = nil, status: Int? = nil, sse: Bool? = nil, frames: Int? = nil, texts: Int? = nil, milliseconds: Int? = nil, code: Int? = nil, route: Route? = nil, state: State? = nil, width: Int? = nil, height: Int? = nil) {
        lock.lock(); defer { lock.unlock() }
        var fields = [ISO8601DateFormatter().string(from: Date()), event.rawValue]
        if let id { fields.append("id=\(id.uuidString)") }
        if let route { fields.append("route=\(route.rawValue)") }
        if let state { fields.append("state=\(state.rawValue)") }
        // Do not retain arbitrary paths (may contain secrets). Only fixed API paths.
        if let url { fields.append("target=\(url.host == nil ? "unknown" : String(url.host!.prefix(253)))\(["/v1/models", "/v1/chat/completions"].contains(url.path) ? url.path : "/other")") }
        if let status { fields.append("status=\(status)") }
        if let sse { fields.append("sse=\(sse)") }
        if let frames { fields.append("frames=\(frames)") }
        if let texts { fields.append("texts=\(texts)") }
        if let milliseconds { fields.append("ms=\(milliseconds)") }
        if let code { fields.append("code=\(code)") }
        if let width { fields.append("width=\(width)") }
        if let height { fields.append("height=\(height)") }
        if event == .app {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "test"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "test"
            fields.append("version=\(version) build=\(build)")
        }
        let row = Data((fields.joined(separator: " ") + "\n").utf8)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let current = directory.appendingPathComponent("current.log")
            var data = (try? Data(contentsOf: current)) ?? Data()
            if data.count + row.count > limit {
                try data.write(to: directory.appendingPathComponent("previous.log"), options: .atomic)
                data = Data()
            }
            data.append(row.prefix(limit))
            try data.write(to: current, options: .atomic)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var folder = directory; try? folder.setResourceValues(values)
        } catch { /* Diagnostics must never interrupt chatting. */ }
    }
    // Allowlisted domain category only; NSError descriptions/userInfo may contain
    // provider paths and filenames. Never log those, including underlying errors.
    public func recordProviderError(_ error: Error) {
        let ns=error as NSError
        let domain: Int
        switch ns.domain { case NSCocoaErrorDomain: domain=1; case NSURLErrorDomain: domain=2; case "PHPhotosErrorDomain": domain=3; case "NSItemProviderErrorDomain": domain=4; default: domain=0 }
        let cancelled = error is CancellationError || (ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError) || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled)
        record(cancelled ? .importCancelled : .providerError,frames:domain,code:ns.code)
        if let underlying=ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            let category = underlying.domain == NSCocoaErrorDomain ? 1 : (underlying.domain == NSURLErrorDomain ? 2:0)
            record(.providerError,frames:category,code:underlying.code)
        }
    }
    public func export() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var data = Data("QiuQiu local diagnostics; no automatic upload\n".utf8)
        var rows = ""
        for name in ["previous.log", "current.log"] { if let part = try? Data(contentsOf: directory.appendingPathComponent(name)) { rows += String(decoding: part, as: UTF8.self) } }
        let scenarios = [("发送", " send "), ("服务器完成", "state=completed"), ("本机确认停止", " stopIntent "), ("本机放弃未提交", " abandonedUnsent "), ("提交后重放", " admissionDispatched "), ("重试暂停", " retryPaused "), ("服务器取消", "state=cancelled"), ("断开", " detach "), ("恢复核实", " resume "), ("网络回退", " pollFallback "), ("真实批准请求", " approvalSeen ")]
        data.append(Data("证据摘要（仅本地保留窗口；观察到不等于测试通过）：\n".utf8))
        for (label, marker) in scenarios { data.append(Data("\(label)：\(rows.contains(marker) ? "已观察" : "未观察/未验证")\n".utf8)) }
        data.append(Data("锁屏与物理设备行为：需实际发生及相应日志，不能由普通前后台事件证明。\n\n".utf8))
        data.append(Data(rows.utf8))
        let file = directory.appendingPathComponent("QiuQiu-diagnostics.txt")
        try data.write(to: file, options: .atomic)
        return file
    }
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        for name in ["current.log", "previous.log", "QiuQiu-diagnostics.txt"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }
}
