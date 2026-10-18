#if os(iOS)
import Foundation
import ImageIO
import UniformTypeIdentifiers

// ImageIO thumbnail decoding bounds decoded pixels, independent of Retina scale.
// Only encoded bytes cross the actor boundary; no full-size UIImage decode on UI.
enum PhotoNormalizer {
    static func normalize(_ bytes: Data) async throws -> ChatAttachment {
        try await Task.detached(priority: .userInitiated) {
            guard !bytes.isEmpty else { throw AttachmentFailure(.emptyData) }
            guard bytes.count <= 64*1024*1024 else { throw AttachmentFailure(.fileSize, bytes:bytes.count) }
            guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache:false] as CFDictionary) else { throw AttachmentFailure(.photoDecode) }
            for pixels in [2048,1536,1024] {
                let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true, kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceThumbnailMaxPixelSize:pixels, kCGImageSourceShouldCacheImmediately:true]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary), image.width <= pixels, image.height <= pixels else { throw AttachmentFailure(.photoDecode) }
                for quality in [0.85,0.7,0.5] {
                    let output = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(output,UTType.jpeg.identifier as CFString,1,nil) else { throw AttachmentFailure(.photoDecode) }
                    CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else { throw AttachmentFailure(.photoDecode) }
                    if output.length <= AttachmentFailure.limit {
                        DiagnosticLog.shared.record(.photoNormalized, frames:max(image.width,image.height), texts:output.length, code:Thread.isMainThread ? 1:0, width:image.width, height:image.height)
                        return try ChatAttachment(name:"photo-\(UUID().uuidString.prefix(8)).jpg",mime:"image/jpeg",data:output as Data)
                    }
                }
            }
            throw AttachmentFailure(.photoDecode)
        }.value
    }
}
#endif
