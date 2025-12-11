//
//  UserIDKeychain.swift
//  nutribench
//

import Foundation
import Security

/// Stable per-installation user identifier, stored in the iOS Keychain.
/// Used to correlate events and health data on the backend.
enum UserID {
    private static let service = "com.ucsb.nutribench"
    private static let account = "user_id"

    /// Read the existing ID from Keychain or create a new UUID and save it.
    static func getOrCreate() -> String {
        if let s = read() { return s }
        let s = UUID().uuidString
        save(s)
        return s
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    private static func save(_ s: String) {
        let data = s.data(using: .utf8)!

        // Delete any existing entry to avoid duplicates.
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)

        // Insert fresh.
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ] as CFDictionary, nil)
    }
}

