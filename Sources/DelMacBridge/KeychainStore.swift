import Foundation
import Security

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.del.mac-bridge"
    private let tokenAccount = "device-token"
    private let configurationKey = "DelMacBridge.configuration"

    private init() {}

    func loadDeviceToken() -> String? {
        readPassword(account: tokenAccount)
    }

    func saveDeviceToken(_ token: String) throws {
        try savePassword(token, account: tokenAccount)
    }

    func deleteDeviceToken() {
        deletePassword(account: tokenAccount)
    }

    func loadConfiguration() -> AppConfiguration? {
        guard
            let data = UserDefaults.standard.data(forKey: configurationKey),
            let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            return nil
        }
        return configuration
    }

    func saveConfiguration(_ configuration: AppConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        UserDefaults.standard.set(data, forKey: configurationKey)
    }

    func deleteConfiguration() {
        UserDefaults.standard.removeObject(forKey: configurationKey)
    }

    private func readPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    private func savePassword(_ password: String, account: String) throws {
        deletePassword(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Could not save token in Keychain."]
            )
        }
    }

    private func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
