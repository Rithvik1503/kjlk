import Foundation
import Security

/// Thin wrapper over the keychain for the one thing worth protecting: the auth session.
///
/// Items are written with `kSecAttrAccessibleAfterFirstUnlock` so a background refresh can
/// still read them while the phone is locked.
enum Keychain {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.aura.roommonitor"
    }

    static func set(_ data: Data, for key: String) {
        var query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func data(for key: String) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    static func encode(_ value: some Encodable, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, for: key)
    }

    static func decode<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = data(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
