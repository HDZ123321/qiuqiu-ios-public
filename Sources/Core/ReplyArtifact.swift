import Foundation

public struct ReplyArtifact: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let mime: String
    public var image: Bool { ["image/png","image/jpeg","image/gif","image/webp"].contains(mime) }
    public func validate() throws {
        guard id.count == 64, id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }), !name.isEmpty,
              name.count <= 255, !name.contains("/"), !name.contains("\\"), !name.hasPrefix("."),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ClientError.message("无效产物信息。") }
    }
}
public struct ReplyArtifacts: Decodable { public let items: [ReplyArtifact] }
