import Foundation

public struct AttachmentFailure: LocalizedError, Equatable {
    public enum Reason: Int { case filenameEmpty = 101, filenameInvalid, emptyData, fileSize, messageCount, messageTotal, unsupportedFormat, providerRead, photoDecode, busy }
    public let reason: Reason
    public let bytes: Int
    public static let limit = 4*1024*1024
    public init(_ reason: Reason, bytes: Int = 0) {
        self.reason = reason; self.bytes = bytes
        DiagnosticLog.shared.record(.attachmentRejected, texts: bytes, code: reason.rawValue)
    }
    public var errorDescription: String? {
        let suffix = "（代码 \(reason.rawValue)）"
        switch reason {
        case .filenameEmpty: return "附件名称为空。" + suffix
        case .filenameInvalid: return "附件名称不安全或过长。" + suffix
        case .emptyData: return "文件提供方返回空内容，请下载文件后重选。" + suffix
        case .fileSize: return "附件大小 \(bytes) 字节，超过 4 MiB（\(Self.limit) 字节）上限；文档不会截断。" + suffix
        case .messageCount: return "每条消息最多 4 个附件。" + suffix
        case .messageTotal: return "附件总计 \(bytes) 字节，超过 4 MiB（\(Self.limit) 字节）。请移除部分附件。" + suffix
        case .unsupportedFormat: return "暂不支持此附件格式。请选择图片、PDF 或 UTF-8 文本。" + suffix
        case .providerRead: return "文件提供方读取失败，请下载文件后重选。" + suffix
        case .photoDecode: return "照片读取或转换失败，请重新选择。" + suffix
        case .busy: return "任务执行中，暂不能添加附件。" + suffix
        }
    }
    public static func validateMessage(count: Int, bytes: Int) throws {
        guard count <= 4 else { throw Self(.messageCount, bytes: bytes) }
        guard bytes <= limit else { throw Self(.messageTotal, bytes: bytes) }
    }
}

public struct ChatAttachment: Codable, Identifiable, Equatable {
    public var id: String { name + String(data.count) }
    public let name: String
    public let mime: String
    public let data: Data
    public init(name: String, mime: String, data: Data) throws {
        guard !name.isEmpty else { throw AttachmentFailure(.filenameEmpty) }
        guard !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"), name.utf8.count <= 180,
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw AttachmentFailure(.filenameInvalid) }
        guard !data.isEmpty else { throw AttachmentFailure(.emptyData) }
        guard data.count <= AttachmentFailure.limit else { throw AttachmentFailure(.fileSize, bytes: data.count) }
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["txt","md","csv","json","log","yaml","yml","pdf","png","jpg","jpeg","gif","webp"].contains(ext) else { throw AttachmentFailure(.unsupportedFormat) }
        self.name = name; self.mime = mime; self.data = data
        DiagnosticLog.shared.record(.attachmentValidated, texts:data.count)
    }
    // Provider display names are not paths. Use a new safe local basename when
    // a legal provider name cannot cross the restricted server filename boundary.
    public static func localName(_ displayName: String, mime: String) throws -> String {
        let ext = (displayName as NSString).pathExtension.lowercased()
        let types = ["txt":"text/plain", "md":"text/markdown", "csv":"text/csv", "json":"application/json", "log":"text/plain", "yaml":"application/yaml", "yml":"application/yaml", "pdf":"application/pdf", "png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "gif":"image/gif", "webp":"image/webp"]
        guard let expected = types[ext], mime == expected || (mime == "text/plain" && ["md","log","yaml","yml"].contains(ext)) else { throw AttachmentFailure(.unsupportedFormat) }
        let safe = !displayName.isEmpty && !displayName.hasPrefix(".") && !displayName.contains("/") && !displayName.contains("\\") && displayName.utf8.count <= 180 && !displayName.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
        return safe ? displayName : "attachment-\(UUID().uuidString.prefix(8)).\(ext)"
    }
    public var payload: [String:String] { ["name":name,"mime":mime,"data":data.base64EncodedString()] }
}
