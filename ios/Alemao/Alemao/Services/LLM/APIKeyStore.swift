import Foundation
import Security

/// Armazena a chave da API Gemini no Keychain.
///
/// Uso:
/// ```
/// try APIKeyStore.shared.set("AIza...", for: .gemini)
/// let key = try APIKeyStore.shared.get(.gemini)
/// ```
enum APIService: String {
    case gemini = "gemini.api.key"
}

enum APIKeyStoreError: Error {
    case notFound
    case keychainError(OSStatus)
}

final class APIKeyStore {
    static let shared = APIKeyStore()
    private let service = "dev.alemao.apikeys"

    private init() {}

    func set(_ value: String, for service: APIService) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: service.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus != errSecSuccess {
                throw APIKeyStoreError.keychainError(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw APIKeyStoreError.keychainError(addStatus)
            }
        default:
            throw APIKeyStoreError.keychainError(status)
        }
    }

    func get(_ service: APIService) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
                throw APIKeyStoreError.notFound
            }
            return str
        case errSecItemNotFound:
            throw APIKeyStoreError.notFound
        default:
            throw APIKeyStoreError.keychainError(status)
        }
    }

    func remove(_ service: APIService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: service.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw APIKeyStoreError.keychainError(status)
        }
    }

    func exists(_ service: APIService) -> Bool {
        (try? get(service)) != nil
    }
}
