import Foundation

public enum ClientError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public struct ServerEndpoint {
    private let base: URL
    public init(_ text: String) throws {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url else { throw ClientError.message("请输入有效 HTTPS 地址，不含账号、查询参数或片段。") }
        base = url
    }
    public func url(for path: String) -> URL {
        let root = base.lastPathComponent == "v1" ? base : base.appendingPathComponent("v1")
        return root.appendingPathComponent(path)
    }
}

public struct ChatMessage: Codable, Identifiable {
    public var id: UUID
    public var role: String
    public var content: String
    public var interrupted: Bool?
    public var attachmentNames: [String]?
    public init(role: String, content: String) { id = UUID(); self.role = role; self.content = content }
}
public struct Chat: Codable, Identifiable {
    public var id: UUID
    public var messages: [ChatMessage]
    public var run: PendingRun?
    public var sessionID: String?
    public var serverSource: ServerSessionSource?
    public var customTitle: String?
    public var pinned: Bool?
    public var archived: Bool?
    public var title: String {
        let name = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? String(messages.first(where: { $0.role == "user" })?.content.prefix(30) ?? "新对话") : name
    }
    public init(messages: [ChatMessage] = []) { id = UUID(); self.messages = messages }
}
public struct ChatRequest: Encodable {
    public let model: String
    public let messages: [ChatMessage]
    public let stream = true
    public init(model: String, messages: [ChatMessage]) { self.model = model; self.messages = messages }
    private struct WireMessage: Encodable { let role: String; let content: String }
    private enum CodingKeys: String, CodingKey { case model, messages, stream }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(stream, forKey: .stream)
        try c.encode(messages.map { WireMessage(role: $0.role, content: $0.content) }, forKey: .messages)
    }
}
public enum StreamDelta {
    public static func decode(_ text: String) throws -> String? {
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw ClientError.message("无效的流响应。")
        }
        if object["error"] != nil { throw ClientError.message("服务器报告流错误，请检查服务端日志。") }
        let choices = object["choices"] as? [[String: Any]]
        return (choices?.first?["delta"] as? [String: Any])?["content"] as? String
    }
}
