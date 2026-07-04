import Foundation
import Security
import CryptoKit

/// Simple Keychain wrapper for sensitive strings (Claude API key, local account password hash).
/// Service: "com.topscan.ScanToExternApp"
enum KeychainManager {
    private static let service = "com.topscan.ScanToExternApp"
    private static let claudeAccount = "claudeAPIKey"
    private static let scanmarkerPasswordAccount = "scanmarkerPasswordHash"

    // MARK: - Generic string read/write/delete

    private static func save(_ value: String, account: String) {
        guard !value.isEmpty else {
            delete(account: account)
            return
        }
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to save \(account): \(status)")
        }
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Local Scanmarker account password
    //
    // This is NOT a real authentication system — Scanmarker's cloud OCR service only checks
    // the email field, no password. This hash is a local-only gate so a user has to confirm
    // "yes, it's me" before changing the Scanmarker email on this machine, e.g. if a shared
    // computer has multiple people's accounts configured. Losing it just means: enter a new
    // password next time you open Settings, same as setting one for the first time.

    static func saveScanmarkerPasswordHash(_ password: String) {
        guard !password.isEmpty else {
            delete(account: scanmarkerPasswordAccount)
            return
        }
        let hash = SHA256.hash(data: Data(password.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        save(hex, account: scanmarkerPasswordAccount)
    }

    static func verifyScanmarkerPassword(_ password: String) -> Bool {
        guard let storedHex = read(account: scanmarkerPasswordAccount) else { return false }
        let hash = SHA256.hash(data: Data(password.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return hex == storedHex
    }

    static func hasScanmarkerPassword() -> Bool {
        read(account: scanmarkerPasswordAccount) != nil
    }

    static func saveClaudeAPIKey(_ key: String) {
        save(key, account: claudeAccount)
    }

    static func getClaudeAPIKey() -> String? {
        read(account: claudeAccount)
    }

    static func deleteClaudeAPIKey() {
        delete(account: claudeAccount)
    }
}
