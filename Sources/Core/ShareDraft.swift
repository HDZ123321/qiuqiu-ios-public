import Foundation

public struct ShareDraft: Codable {
    public let id: UUID
    public var text: String
    public var files: [ChatAttachment]
    public let scope: String
}
extension Chat {
    public mutating func importShare(_ item: ShareInbox.Item, scope: String, expectedScope: String) throws {
        guard scope == expectedScope, serverSource == nil || serverSource?.scope == scope else { throw ClientError.message("连接已变化或此对话属于其他连接，请重新选择；分享仍保留。") }
        if importedShareIDs?.contains(item.id) == true { return }
        guard run?.terminal != false, archived != true else { throw ClientError.message("目标对话正在执行任务或已归档，不能导入；分享仍保留。") }
        guard shareDraft == nil else { throw ClientError.message("此对话已有分享草稿，请先处理；不会覆盖原草稿。") }
        try ShareInbox.validate(text: item.text, files: item.files)
        shareDraft = ShareDraft(id: item.id, text: item.text, files: item.files, scope: scope)
        // Retain replay identity after send; bounded history covers inbox capacity.
        importedShareIDs = Array(((importedShareIDs ?? []) + [item.id]).suffix(256))
    }
}
