import Foundation
import Security

final class AuthSessionStore {
    static let shared = AuthSessionStore()

    private let service = "com.kgeneye.io.auth"
    private let account = "session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> StoredAuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? decoder.decode(StoredAuthSession.self, from: data)
    }

    func save(_ session: StoredAuthSession) throws {
        let data = try encoder.encode(session)
        var query = baseQuery()

        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AuthError.server("Keychain save failed (\(addStatus)).")
        }
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
