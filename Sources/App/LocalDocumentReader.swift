#if os(iOS)
import Foundation

// Provider URLs must be read under a coordinated security-scoped lease. Missing
// pre-materialization size metadata is NOT evidence that the file exceeds limits.
enum LocalDocumentReader {
    static func read(_ url: URL) async throws -> Data {
        DiagnosticLog.shared.record(.importSelected)
        do {
        let data = try await Task.detached(priority:.userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var result: Result<Data,Error> = .failure(ClientError.message("文件提供方未返回内容。"))
            NSFileCoordinator().coordinate(readingItemAt:url,options:[],error:&coordinationError) { coordinated in
                result = Result {
                    let values = try coordinated.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey])
                    guard values.isSymbolicLink != true, values.isRegularFile != false else { throw ClientError.message("只能导入普通文件。") }
                    if let size=values.fileSize, size>AttachmentFailure.limit { throw AttachmentFailure(.fileSize, bytes:size) }
                    let handle = try FileHandle(forReadingFrom:coordinated)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount:4*1024*1024+1) ?? Data()
                    guard !data.isEmpty else { throw AttachmentFailure(.emptyData) }
                    guard data.count<=AttachmentFailure.limit else { throw AttachmentFailure(.fileSize, bytes:data.count) }
                    return data
                }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }.value
        DiagnosticLog.shared.record(.importRead, texts:data.count)
        return data
        } catch {
            DiagnosticLog.shared.record(.importFailed,code:(error as NSError).code)
            if let failure = error as? AttachmentFailure { throw failure }
            throw AttachmentFailure(.providerRead)
        }
    }
}
#endif
