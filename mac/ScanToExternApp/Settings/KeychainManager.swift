import Foundation
import Security

/// Simple Keychain wrapper for sensitive strings (Claude API key).
/// Service: "com.topscan.ScanToExternApp"
/// Account: "claudeAPIKey"
enum KeychainManager {
    private static let service = "com.topscan.ScanToExternApp"
    private static let claudeAccount = "claudeAPIKey"

    static func saveClaudeAPIKey(_ key: String) {
        guard !key.isEmpty else {
            deleteClaudeAPIKey()
            return
        }

        let data = Data(key.utf8)

        // First delete any existing
        deleteClaudeAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: claudeAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to save Claude key: \(status)")
        }
    }

    static func getClaudeAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: claudeAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    static func deleteClaudeAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: claudeAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
