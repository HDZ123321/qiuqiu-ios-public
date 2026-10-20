#if os(iOS)
import Foundation
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import HermesCore
#endif

/// Official providers only. Sequential materialization bounds peak memory; any
/// failed item rejects the entire batch. No URL fetching or provider-name paths.
enum ShareProviderIntake {
    struct Result { let text: String; let files: [ChatAttachment] }
    static func load(_ providers: [NSItemProvider]) async throws -> Result {
        guard !providers.isEmpty, providers.count <= 4 else { throw ClientError.message("每次最多分享 4 项；未保存任何内容。") }
        var texts: [String] = [], files: [ChatAttachment] = []
        for provider in providers {
            try Task.checkCancellation()
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data = try await fileBytes(provider, type: UTType.image.identifier, limit: 64*1024*1024)
                files.append(try await PhotoNormalizer.normalize(data))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let object = try await item(provider, type: UTType.fileURL.identifier)
                guard let url = object as? URL, url.isFileURL else { throw AttachmentFailure(.providerRead) }
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let name = try ChatAttachment.localName(url.lastPathComponent, mime: mime)
                let bytes = try await LocalDocumentReader.read(url)
                files.append(try ChatAttachment(name: name, mime: mime, data: bytes))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) || provider.registeredTypeIdentifiers.contains(where: { UTType($0)?.conforms(to: .data) == true && UTType($0)?.conforms(to: .text) != true && UTType($0)?.conforms(to: .url) != true }) {
                guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true && $0 != UTType.fileURL.identifier }) ?? provider.registeredTypeIdentifiers.first else { throw AttachmentFailure(.unsupportedFormat) }
                let bytes = try await fileBytes(provider, type: type, limit: AttachmentFailure.limit)
                let ext = UTType(type)?.preferredFilenameExtension ?? ""
                let mime = UTType(type)?.preferredMIMEType ?? "application/octet-stream"
                let name = try ChatAttachment.localName(provider.suggestedName.flatMap { ($0 as NSString).pathExtension.isEmpty ? $0+"."+ext : $0 } ?? "shared-"+UUID().uuidString+"."+ext, mime: mime)
                files.append(try ChatAttachment(name: name, mime: mime, data: bytes))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                let object: NSSecureCoding
                if provider.canLoadObject(ofClass: NSURL.self) {
                    object = try await withCheckedThrowingContinuation { continuation in
                        _ = provider.loadObject(ofClass: NSURL.self) { value, error in
                            if let value { continuation.resume(returning: value) }
                            else { continuation.resume(throwing: error ?? AttachmentFailure(.providerRead)) }
                        }
                    }
                } else { object = try await item(provider, type: UTType.url.identifier) }
                #if DEBUG && targetEnvironment(simulator)
                print("SHARE_URL_REPRESENTATION", String(describing: type(of: object)), (object as? URL)?.scheme ?? "none")
                #endif
                let urlValue: URL?
                if let url = object as? URL { urlValue = url }
                else if let data = object as? Data, data.count <= ShareInbox.maxText, let string = String(data: data, encoding: .utf8) { urlValue = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) }
                else if let string = object as? String { urlValue = URL(string: string) }
                else { urlValue = nil }
                guard let url = urlValue, url.absoluteString.utf8.count <= ShareInbox.maxText,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
                      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil else { throw ClientError.message("只接收普通 HTTP/HTTPS 网页链接，不读取本地路径。") }
                texts.append(url.absoluteString)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                // A file-backed text document should retain its bytes/name.
                let object = try await item(provider, type: UTType.plainText.identifier)
                if let url = object as? URL, url.isFileURL {
                    let bytes = try await LocalDocumentReader.read(url)
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "text/plain"
                    let name = try ChatAttachment.localName(url.lastPathComponent, mime: mime)
                    files.append(try ChatAttachment(name: name, mime: mime, data: bytes))
                } else if let string = object as? String {
                    guard string.utf8.count <= ShareInbox.maxText else { throw ClientError.message("分享文字超过 64 KiB，未截断保存。") }
                    texts.append(string)
                }
                else if let data = object as? Data, data.count <= ShareInbox.maxText, let string = String(data: data, encoding: .utf8) { texts.append(string) }
                else { throw ClientError.message("无法读取分享文字，未保存任何内容。") }
            } else { throw AttachmentFailure(.unsupportedFormat) }
            try ShareInbox.validate(text: texts.joined(separator: "\n\n"), files: files)
        }
        return Result(text: texts.joined(separator: "\n\n"), files: files)
    }
    private static func item(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: AttachmentFailure(.providerRead)) }
            }
        }
    }
    private static func fileBytes(_ provider: NSItemProvider, type: String, limit: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if error != nil { continuation.resume(throwing: AttachmentFailure(.providerRead)); return }
                guard let url else { continuation.resume(throwing: AttachmentFailure(.providerRead)); return }
                // Temporary URL is valid only during this callback. Coordinate and
                // consume here, never dispatch an async read of the expired URL.
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                var coordinationError: NSError?
                var result: Swift.Result<Data, Error> = .failure(AttachmentFailure(.providerRead))
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { value in
                    result = Swift.Result {
                        let metadata = try value.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else { throw AttachmentFailure(.providerRead) }
                        if let size = metadata.fileSize, size > limit { throw AttachmentFailure(.fileSize, bytes: size) }
                        let handle = try FileHandle(forReadingFrom: value); defer { try? handle.close() }
                        let bytes = try handle.read(upToCount: limit+1) ?? Data()
                        guard !bytes.isEmpty else { throw AttachmentFailure(.emptyData) }
                        guard bytes.count <= limit else { throw AttachmentFailure(.fileSize, bytes: bytes.count) }
                        return bytes
                    }
                }
                if coordinationError != nil { continuation.resume(throwing: AttachmentFailure(.providerRead)) }
                else { continuation.resume(with: result) }
            }
        }
    }
}
#endif
