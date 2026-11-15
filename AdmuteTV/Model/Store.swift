import Foundation
import Security

/// Where the app keeps the studio's address (UserDefaults) and the session cookie (Keychain).
/// The password itself is never kept: the session lasts 30 days, then the app asks again.
enum Store {
    private static let serverKey = "server", userKey = "username"
    private static let service = "admute-tv.session"

    static var server: String? {
        get { UserDefaults.standard.string(forKey: serverKey) }
        set { UserDefaults.standard.set(newValue, forKey: serverKey) }
    }

    static var username: String? {
        get { UserDefaults.standard.string(forKey: userKey) }
        set { UserDefaults.standard.set(newValue, forKey: userKey) }
    }

    static func session(for server: String) -> Session? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: server, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func setSession(_ session: Session?, for server: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: server]
        SecItemDelete(q as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
