import Foundation

public struct RunApproval: Codable, Equatable {
    public var request_id: String?
    public var command: String?
    public var description: String?
    public var choices: [String]?
}

// The exact request bytes and key are persisted before the first POST. Never rebuild a retry.
public struct PendingRun: Codable, Equatable {
    public var key: String
    public var body: Data
    public var replyID: UUID
    public var runID: String?
    public var sessionID: String?
    public var createdAt: Date
    public var status: String
    public var output: String?
    public var approval: RunApproval?
    // nil is a pre-Build5 record: submission is ambiguous, never locally abandon it.
    public var admissionDispatched: Bool? = false
    public var definitelyUnsent: Bool { admissionDispatched == false && runID == nil }
    public var stopRequested: Bool = false
    public var terminal: Bool { ["completed", "failed", "cancelled", "interrupted"].contains(status) }
    public var label: String {
        switch status {
        case "creating": return "正在确认任务（可安全重连）"
        case "queued", "started": return "已排队"
        case "running": return "服务器正在执行"
        case "waiting_for_approval": return "等待你的批准"
        case "stopping": return "正在停止 · 执行器仍可能运行"
        case "completed": return "已完成"
        case "cancelled": return definitelyUnsent ? "已在本机放弃 · 未提交服务器" : "服务器已取消"
        case "interrupted": return "服务重启或中断 · 任务未完成"
        case "failed": return "服务器执行失败"
        default: return "服务器状态：\(status)"
        }
    }
    public init(input: String, model: String, sessionID: String?, history: [ChatMessage], replyID: UUID, attachments: [ChatAttachment] = []) throws {
        key = UUID().uuidString; self.replyID = replyID; self.sessionID = sessionID
        createdAt = Date(); status = "creating"
        try AttachmentFailure.validateMessage(count: attachments.count, bytes: attachments.reduce(0, { $0 + $1.data.count }))
        var payload: [String: Any] = ["input": input, "model": model, "artifact_delivery": "workspace-file-v2"]
        if !attachments.isEmpty { payload["attachments"] = attachments.map(\.payload) }
        if let sessionID { payload["session_id"] = sessionID }
        else if !history.isEmpty {
            payload["conversation_history"] = history.filter { !$0.content.isEmpty && $0.interrupted != true }.map { ["role": $0.role, "content": $0.wireContent] }
        }
        body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
    public mutating func apply(_ data: Data) throws {
        struct Snapshot: Decodable {
            let run_id: String
            let status: String
            let session_id: String?
            let output: String?
            let approval: RunApproval?
        }
        let value = try JSONDecoder().decode(Snapshot.self, from: data)
        guard runID == nil || runID == value.run_id else { throw ClientError.message("任务编号不匹配。") }
        // A terminal create replay can omit output; the authoritative GET hydrates it.
        // Never let stale progress or a conflicting terminal overwrite final state.
        guard !terminal || status == value.status else { return }
        runID = value.run_id; status = value.status
        if let session = value.session_id { sessionID = session }
        if let text = value.output { output = text }
        approval = value.approval
    }
}
