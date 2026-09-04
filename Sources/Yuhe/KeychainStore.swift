import Foundation
import Security

enum KeychainStore {
    private static let service = "app.yuhe.quota"
    private static let account = "deepseek.api-key"

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/yuhe/deepseek.key")
    }

    static func loadDeepSeekKey() -> String? {
        if let key = readFile(), !key.isEmpty { return key }
        if let key = readKeychain(), !key.isEmpty {
            try? writeFile(key)
            return key
        }
        return nil
    }

    static func saveDeepSeekKey(_ key: String) {
        try? writeFile(key)
        writeKeychain(key)
    }

    static func deleteDeepSeekKey() {
        deleteSecret(account: account, fileName: "deepseek.key")
    }

    static func loadGLMKey() -> String? {
        loadSecret(account: "glm.api-key", fileName: "glm.key")
    }

    static func saveSecret(_ key: String, account: String, fileName: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/yuhe/\(fileName)")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(key.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        deleteKeychainAccount(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadSecret(account: String, fileName: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/yuhe/\(fileName)")
        if let raw = try? String(contentsOf: url, encoding: .utf8) {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return readKeychainAccount(account)
    }

    static func deleteSecret(account: String, fileName: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/yuhe/\(fileName)")
        try? FileManager.default.removeItem(at: url)
        deleteKeychainAccount(account)
    }

    private static func readFile() -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private static func writeFile(_ key: String) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(key.utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ key: String) {
        deleteKeychainOnly()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteKeychainOnly() {
        deleteKeychainAccount(account)
    }

    private static func readKeychainAccount(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainAccount(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

}
