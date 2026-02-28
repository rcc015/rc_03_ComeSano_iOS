import Foundation
import Security

@MainActor
final class OpenAIKeychainStore: ObservableObject {
    @Published private(set) var hasStoredKey: Bool = false

    private let service: String
    private let account: String

    init(service: String = "rcTools.ComeSano", account: String = "openai_api_key") {
        self.service = service
        self.account = account
        hasStoredKey = currentKey() != nil
    }

    func currentKey() -> String? {
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
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }

        return key
    }

    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainError.emptyValue
        }

        let data = Data(trimmed.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            hasStoredKey = true
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
            hasStoredKey = true
            return
        }

        throw KeychainError.osStatus(updateStatus)
    }

    func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }

        hasStoredKey = false
    }
}

enum KeychainError: LocalizedError {
    case emptyValue
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyValue:
            return "La API key no puede estar vacía."
        case let .osStatus(status):
            return "Error de Keychain (\(status))."
        }
    }
}
