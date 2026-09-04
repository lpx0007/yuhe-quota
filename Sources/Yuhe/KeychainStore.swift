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
        if let key = importFromKnownDotEnvs(), !key.isEmpty {
            saveDeepSeekKey(key)
            return key
        }
        return nil
    }

    static func saveDeepSeekKey(_ key: String) {
        try? writeFile(key)
        writeKeychain(key)
    }

    static func deleteDeepSeekKey() {
        try? FileManager.default.removeItem(at: fileURL)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func importFromKnownDotEnvs() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = [
            home.appendingPathComponent(".reasonix/.env"),
            home.appendingPathComponent("工作盘/动态网站本地版/pentagi/.env"),
        ]
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let raw = String(line).trimmingCharacters(in: .whitespaces)
                guard raw.hasPrefix("DEEPSEEK_API_KEY=") else { continue }
                var value = String(raw.dropFirst("DEEPSEEK_API_KEY=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("\"") && value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}
