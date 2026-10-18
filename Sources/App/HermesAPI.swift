import Foundation
#if SWIFT_PACKAGE
import HermesCore
#endif

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct HTTPFailure: Error, CustomNSError, LocalizedError {
    let status: Int
    static var errorDomain: String { "QiuQiu.HTTP" }
    var errorCode: Int { status }
    var errorDescription: String? { "HTTP \(status)：请检查服务地址、令牌与网络。" }
    var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: errorDescription!] }
}

final class HermesAPI {
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 1800
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    private func request(_ path: String, settings: ConnectionSettings) throws -> URLRequest {
        guard !settings.bearer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClientError.message("请先在设置中保存 Bearer Token。") }
        var request = URLRequest(url: try ServerEndpoint(settings.serverURL).url(for: path))
        request.setValue("Bearer \(settings.bearer)", forHTTPHeaderField: "Authorization")
        return request
    }
    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.message("无效 HTTP 响应。") }
        guard (200..<300).contains(http.statusCode) else { throw HTTPFailure(status: http.statusCode) }
    }
    private func workspaceRequest(_ settings: ConnectionSettings, path: String, content: Bool) throws -> URLRequest {
        if !path.isEmpty { try WorkspacePath.validate(path) }
        var req = try request(content ? "workspace/content" : "workspace", settings: settings)
        var url = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "path", value: path)]
        req.url = url.url
        req.timeoutInterval = 45
        return req
    }
    func workspaceList(_ settings: ConnectionSettings, path: String) async throws -> WorkspaceListing {
        let (data,response) = try await session.data(for: workspaceRequest(settings,path:path,content:false))
        try validate(response)
        return try JSONDecoder().decode(WorkspaceListing.self,from:data)
    }
    func workspaceRead(_ settings: ConnectionSettings, path: String) async throws -> (data: Data, etag: String) {
        let (data,response) = try await session.data(for: workspaceRequest(settings,path:path,content:true))
        try validate(response)
        guard data.count <= 4*1024*1024, let etag=(response as? HTTPURLResponse)?.value(forHTTPHeaderField:"ETag") else { throw ClientError.message("文件过大或缺少版本标识。") }
        return (data,etag)
    }
    func workspaceWrite(_ settings: ConnectionSettings, path: String, data: Data, etag: String?) async throws {
        guard data.count <= 4*1024*1024 else { throw ClientError.message("文件上限为 4 MB。") }
        var req = try workspaceRequest(settings,path:path,content:true)
        req.httpMethod = etag == nil ? "POST" : "PUT"; req.httpBody = data
        req.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
        if let etag { req.setValue(etag,forHTTPHeaderField:"If-Match") }
        let id=UUID()
        DiagnosticLog.shared.record(.uploadStart,id:id,texts:data.count)
        do {
            let (_,response) = try await session.data(for:req)
            try validate(response)
            let verified = try await workspaceRead(settings,path:path)
            guard verified.data == data else { throw ClientError.message("上传回读核实失败。") }
            DiagnosticLog.shared.record(.uploadVerified,id:id,status:(response as? HTTPURLResponse)?.statusCode)
        } catch { DiagnosticLog.shared.record(.uploadFailed,id:id,code:(error as NSError).code); throw error }
    }
    func models(_ settings: ConnectionSettings) async throws -> [String] {
        let id = UUID()
        DiagnosticLog.shared.record(.requestStart, id: id, url: try? ServerEndpoint(settings.serverURL).url(for: "models"))
        let (data, response) = try await session.data(for: request("models", settings: settings))
        DiagnosticLog.shared.record(.response, id: id, status: (response as? HTTPURLResponse)?.statusCode)
        try validate(response)
        struct ModelList: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)
    }
    func stream(_ settings: ConnectionSettings, messages: [ChatMessage], onText: @MainActor (String) -> Void, onTool: @MainActor (String) -> Void) async throws {
        var request = try request("chat/completions", settings: settings)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: settings.model, messages: messages))
        try await streamRequest(request, onText: onText, onTool: onTool)
    }
    func verifyChat(_ settings: ConnectionSettings, onVerified: @escaping @MainActor () -> Void) async throws {
        var req = try request("chat/completions", settings: settings)
        req.httpMethod = "POST"; req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.model, "stream": true, "max_tokens": 16, "tool_choice": "none", "messages": [["role": "user", "content": "Connectivity check. Reply only OK. Do not use tools or save memory."]]])
        DiagnosticLog.shared.record(.probe)
        let probe = Task { try await self.verifyStreamRequest(req, onVerified: onVerified) }
        let deadline = Task {
            do { try await Task.sleep(nanoseconds: 45_000_000_000); probe.cancel() }
            catch {}
        }
        defer { deadline.cancel() }
        try await withTaskCancellationHandler(operation: { try await probe.value }, onCancel: { probe.cancel() })
    }
    func verifyStreamRequest(_ request: URLRequest, onVerified: @MainActor () -> Void) async throws {
        try await streamRequest(request, onText: { _ in }, onTool: { _ in })
        try Task.checkCancellation()
        await onVerified()
    }
    func runRequest(_ settings: ConnectionSettings, path: String, method: String = "GET", body: Data? = nil, key: String? = nil, correlation: UUID? = nil) async throws -> Data {
        var req = try request(path, settings: settings)
        req.httpMethod = method; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { req.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        let id = UUID()
        let route = DiagnosticLog.route(path), start = Date()
        DiagnosticLog.shared.record(.requestStart, id: correlation ?? id, route: route)
        let (data, response) = try await session.data(for: req)
        DiagnosticLog.shared.record(.response, id: correlation ?? id, status: (response as? HTTPURLResponse)?.statusCode, milliseconds: Int(Date().timeIntervalSince(start) * 1000), route: route)
        if (response as? HTTPURLResponse)?.statusCode == 409 { throw HTTPFailure(status: 409) }
        try validate(response)
        return data
    }
    func sessionTranscript(_ settings: ConnectionSettings, id: String, profile: Bool = false) async throws -> [ServerSessionMessages] {
        var pages: [ServerSessionMessages] = [], cursor: Int?, seen = Set<Int>(), bytes = 0
        repeat {
            try Task.checkCancellation()
            let data = try await sessionRead(settings,id:id,messages:true,cursor:cursor,profile:profile)
            bytes += data.count
            guard bytes <= 16*1024*1024, pages.count < 1000 else { throw ClientError.message("历史超出安全读取上限，未导入部分历史。") }
            let page = try JSONDecoder().decode(ServerSessionMessages.self,from:data)
            guard page.session_id == id, ["stored_text","unavailable"].contains(page.history) else { throw ClientError.message("会话身份不匹配。") }
            pages.append(page)
            cursor = page.next_offset
            if let cursor { guard cursor > 0, seen.insert(cursor).inserted else { throw ClientError.message("历史分页无进展。") } }
        } while cursor != nil
        return pages
    }
    func sessionRead(_ settings: ConnectionSettings, id: String? = nil, messages: Bool = false, cursor: Int? = nil, profile: Bool = false, kind: String = "conversations") async throws -> Data {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-sessions") {
            if ProcessInfo.processInfo.arguments.contains("--ui-sessions-paged") {
                if messages {
                    return try JSONSerialization.data(withJSONObject: ["session_id":id ?? "fixture_readonly","history":"stored_text","items":[["id":"read1","role":"user","content":"Read-only WeChat fixture"]],"next_offset":NSNull()])
                }
                let older = cursor != nil
                let items: [[String:Any]] = older
                    ? [["session_id":"fixture_readonly","created_seq":1,"run_count":0,"history":"explicit_fetch","title":"WeChat archived fixture","source":"weixin","can_continue":false,"archived":true,"hidden":false]]
                    : (2...51).reversed().map { n in ["session_id":"fixture_page_\(n)","created_seq":n,"run_count":1,"history":"explicit_fetch","title":"Fixture \(n)","source":"api_server","can_continue":true] }
                return try JSONSerialization.data(withJSONObject: ["items":items,"total":51,"next_cursor":older ? NSNull() as Any : 2 as Any,"has_more":!older])
            }
            if messages {
                return Data(#"{"session_id":"fixture_owned","history":"stored_text","items":[{"id":"1","role":"user","content":"Historical garden question"},{"id":"2","role":"assistant","content":"Historical garden answer"}],"next_offset":null}"#.utf8)
            }
            return Data(#"{"items":[{"session_id":"fixture_owned","created_seq":1,"run_count":1,"history":"explicit_fetch","title":"Garden planning","title_source":"native"}],"next_cursor":null}"#.utf8)
        }
        #endif
        if let id {
            guard !id.isEmpty, id.count <= 200, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw ClientError.message("无效会话编号。") }
        }
        let path = (profile ? "profile/sessions" : "app/sessions") + (id.map { "/" + $0 } ?? "") + (messages ? "/messages" : "")
        var req = try request(path, settings: settings)
        var components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")]
        if profile && id == nil { components.queryItems?.append(URLQueryItem(name: "kind", value: kind)) }
        if let cursor { components.queryItems?.append(URLQueryItem(name: messages ? "offset" : "before", value: String(cursor))) }
        req.url = components.url; req.timeoutInterval = 25
        let correlation = UUID()
        DiagnosticLog.shared.record(.requestStart, id: correlation, route: messages ? .sessionMessages : .sessionList)
        do {
            let (data, response) = try await session.data(for: req)
            DiagnosticLog.shared.record(.response, id: correlation, status: (response as? HTTPURLResponse)?.statusCode, route: messages ? .sessionMessages : .sessionList)
            try validate(response)
            guard data.count <= 2*1024*1024 else { throw ClientError.message("历史分页过大。") }
            return data
        } catch {
            DiagnosticLog.shared.record(.error, id: correlation, code: (error as NSError).code, route: messages ? .sessionMessages : .sessionList)
            throw error
        }
    }
    func adoptSession(_ settings: ConnectionSettings, id: String) async throws {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-sessions") { return }
        #endif
        guard !id.isEmpty, id.count <= 200, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw ClientError.message("无效会话编号。") }
        var req = try request("profile/sessions/" + id + "/adopt", settings: settings)
        req.httpMethod = "POST"; req.timeoutInterval = 20
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }
    func sessionSync(_ settings: ConnectionSettings, id: String) async throws -> ServerSessionSync {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-sessions") {
            let body = ProcessInfo.processInfo.arguments.contains("--ui-sync-active")
                ? #"{"session_id":"fixture_owned","channel_active":true,"server_state":"running","last_checked":1,"can_continue":false}"#
                : #"{"session_id":"fixture_owned","channel_active":false,"server_state":"completed","last_checked":1,"can_continue":true}"#
            return try JSONDecoder().decode(ServerSessionSync.self, from: Data(body.utf8))
        }
        #endif
        guard !id.isEmpty, id.count <= 200, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw ClientError.message("无效会话编号。") }
        var req = try request("app/sessions/sync/" + id, settings: settings)
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try JSONDecoder().decode(ServerSessionSync.self, from: data)
    }
    func runEvents(_ settings: ConnectionSettings, runID: String, correlation: UUID? = nil, onEvent: @MainActor (SSEEvent) -> Void) async throws {
        try await runEventsRequest(request("runs/\(runID)/events", settings: settings), correlation: correlation, onEvent: onEvent)
    }
    func runEventsRequest(_ req: URLRequest, correlation: UUID? = nil, onEvent: @MainActor (SSEEvent) -> Void) async throws {
        let id = correlation ?? UUID(), start = Date()
        var frames = 0, texts = 0
        DiagnosticLog.shared.record(.requestStart, id: id, route: .events)
        defer { DiagnosticLog.shared.record(Task.isCancelled ? .detach : .streamEnd, id: id, frames: frames, texts: texts, milliseconds: Int(Date().timeIntervalSince(start) * 1000), route: .events) }
        let (bytes, response) = try await session.bytes(for: req)
        DiagnosticLog.shared.record(.response, id: id, status: (response as? HTTPURLResponse)?.statusCode, route: .events)
        try validate(response)
        guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else { throw ClientError.message("任务流格式不正确。") }
        var parser = SSEByteParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            if let event = parser.feed(byte) {
                frames += 1
                if event.event == "message.delta" {
                    if texts == 0 { DiagnosticLog.shared.record(.firstToken, id: id, milliseconds: Int(Date().timeIntervalSince(start) * 1000), route: .events) }
                    texts += 1
                }
                await onEvent(event)
            }
        }
    }
    // Shared production transport seam; callers build/validate HTTPS settings above.
    func streamRequest(_ request: URLRequest, onText: @MainActor (String) -> Void, onTool: @MainActor (String) -> Void) async throws {
        let id = UUID(), start = Date()
        var frames = 0, texts = 0, completed = false
        var errorCode: Int?
        DiagnosticLog.shared.record(.requestStart, id: id, url: request.url)
        defer { DiagnosticLog.shared.record(completed ? .done : (Task.isCancelled ? .cancel : .error), id: id, frames: frames, texts: texts, milliseconds: Int(Date().timeIntervalSince(start) * 1000), code: errorCode) }
        do {
        let (bytes, response) = try await session.bytes(for: request)
        DiagnosticLog.shared.record(.response, id: id, status: (response as? HTTPURLResponse)?.statusCode, sse: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true)
        try validate(response)
        guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw ClientError.message("服务器未返回 SSE 流。") }
        var parser = SSEByteParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard let event = parser.feed(byte) else { continue }
            frames += 1
            if event.event == "hermes.tool.progress" { await onTool(event.data); continue }
            if event.event == "error" { throw ClientError.message("服务器报告流错误，请检查服务端日志。") }
            guard event.event == "message" || event.event == "chat.completion.chunk" else { continue }
            if event.data == "[DONE]" {
                guard texts > 0 else { throw ClientError.message("服务器结束了回复，但没有返回文字。请导出诊断日志。") }
                try Task.checkCancellation()
                completed = true; return
            }
            if let text = try StreamDelta.decode(event.data), !text.isEmpty {
                if texts == 0 { DiagnosticLog.shared.record(.firstToken, id: id, milliseconds: Int(Date().timeIntervalSince(start) * 1000)) }
                texts += 1; await onText(text)
            }
        }
        throw ClientError.message("连接在 [DONE] 前断开；已保留部分回复。")
        } catch { errorCode = (error as NSError).code; throw error }
    }
}
