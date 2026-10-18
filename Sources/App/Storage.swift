import Foundation
import Security
#if SWIFT_PACKAGE
import HermesCore
#endif

enum CredentialStore {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.hermesclient.qiuqiu", kSecAttrAccount as String: "connection"] }
    static func load() throws -> ConnectionSettings {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return ConnectionSettings() }
        guard status == errSecSuccess, let data = item as? Data else { throw ClientError.message("无法读取钥匙串 (\(status))。") }
        return try JSONDecoder().decode(ConnectionSettings.self, from: data)
    }
    static func save(_ settings: ConnectionSettings) throws {
        let data = try JSONEncoder().encode(settings)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClientError.message("无法保存钥匙串 (\(status))。") }
    }
}

// No URL, bearer token or model settings are written to the chat file.
enum ChatDisk {
    private static func file() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return directory.appendingPathComponent("chats.json")
    }
    static func load() throws -> [Chat] {
        let url = try file()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Chat].self, from: Data(contentsOf: url))
    }
    static func save(_ chats: [Chat]) throws {
        let url = try file()
        #if os(iOS)
        try JSONEncoder().encode(chats).write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try JSONEncoder().encode(chats).write(to: url, options: [.atomic])
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
