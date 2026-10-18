import Foundation

public struct ConnectionSettings: Codable, Equatable {
    public var serverURL = ""
    public var bearer = ""
    public var model = "hermes"
    public init() {}
}
