#if os(iOS)
import Foundation
#if SWIFT_PACKAGE
import HermesCore
#endif

enum ShareContainer {
    static func open() throws -> ShareInbox {
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
