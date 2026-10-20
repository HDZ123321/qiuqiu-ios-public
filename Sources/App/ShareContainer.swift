#if os(iOS)
import Foundation
#if SWIFT_PACKAGE
import HermesCore
#endif

enum ShareContainer {
    static func open() throws -> ShareInbox {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-share-isolated") {
            // Explicit isolated UI fixture, NOT an App Group capability fallback.
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("share-isolated-ui")
            if ProcessInfo.processInfo.arguments.contains("--ui-share-reset") { try? FileManager.default.removeItem(at: root) }
            let inbox = try ShareInbox(container: root)
            if try inbox.list().isEmpty {
                _ = try inbox.save(text: "External synthetic share text · not sent", files: [ChatAttachment(name: "fixture.txt", mime: "text/plain", data: Data("synthetic document".utf8))])
            }
            return inbox
        }
        #endif
        guard let group = Bundle.main.object(forInfoDictionaryKey: "QiuShareAppGroup") as? String,
              group.hasPrefix("group."), !group.contains("$("),
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw ClientError.message(ShareInbox.unavailable)
        }
        let inbox = try ShareInbox(container: url)
        try inbox.checkWritable()
        return inbox
    }
}
#endif
