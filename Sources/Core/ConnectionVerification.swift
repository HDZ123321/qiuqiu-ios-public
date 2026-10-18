import Foundation
public struct ConnectionVerification {
    public enum Phase { case notTested, checking, authenticated, verified, failed }
    public private(set) var phase: Phase = .notTested
    public private(set) var date: Date?
    private var attempt: UUID?
    public init() {}
    public mutating func begin() -> UUID { let id = UUID(); attempt = id; phase = .checking; date = nil; return id }
    public mutating func invalidate() { attempt = nil; phase = .notTested; date = nil }
    public mutating func authenticated(_ id: UUID) { if attempt == id { phase = .authenticated } }
    @discardableResult public mutating func complete(_ id: UUID) -> Bool {
        guard attempt == id, phase == .authenticated else { return false }
        phase = .verified; date = Date(); return true
    }
    public mutating func fail(_ id: UUID) { if attempt == id { phase = .failed; date = nil } }
}
