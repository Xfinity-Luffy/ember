import Foundation
import Security

/// Keeps each vehicle's 32-byte bridge key in the iOS Keychain (never in UserDefaults).
/// `account` is the vehicle's ID; "default" is where the single-car version kept it.
enum SecretStore {
    private static let service = "app.ember.bridge-key"
    static let legacyAccount = "default"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load(account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    static func save(_ key: Data, account: String) -> Bool {
        delete(account: account)
        var query = baseQuery(account)
        query[kSecValueData as String] = key
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    /// Accepts the 64-character hex string from `openssl rand -hex 32`
    /// (spaces, dashes and line breaks are ignored).
    static func parseHex(_ text: String) -> Data? {
        let hex = text.lowercased().filter { $0.isHexDigit }
        guard hex.count == 64,
              text.filter({ !$0.isWhitespace && $0 != "-" }).count == 64 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let b = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(b)
            index = next
        }
        return Data(bytes)
    }
}
