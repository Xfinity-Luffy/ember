import Foundation
import Security

/// Keeps the 32-byte bridge key in the iOS Keychain (never in UserDefaults).
enum SecretStore {
    private static let service = "app.ember.bridge-key"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    static func save(_ key: Data) -> Bool {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = key
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
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
