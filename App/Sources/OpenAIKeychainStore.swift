import Foundation
import Security
import ComeSanoAI

@MainActor
final class AIKeychainStore: ObservableObject {
    @Published private(set) var hasOpenAIKey = false
    @Published private(set) var hasGeminiKey = false
    @Published private(set) var hasSharedGeminiKey = false
    @Published private(set) var hasBundledGeminiKey = false
    @Published var primaryProvider: AIProviderChoice

    private let service: String

    init(service: String = "rcTools.ComeSano") {
        self.service = service

        let savedProviderRaw = UserDefaults.standard.string(forKey: "ai_primary_provider")
        self.primaryProvider = AIProviderChoice(rawValue: savedProviderRaw ?? "gemini") ?? .gemini

        refreshFlags()
    }

    func refreshFlags() {
        hasOpenAIKey = key(for: .openAI) != nil
        hasGeminiKey = key(for: .gemini) != nil
        hasSharedGeminiKey = sharedGeminiKey() != nil
        hasBundledGeminiKey = bundledGeminiKey() != nil
    }

    func key(for provider: AIProviderChoice) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
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

    func saveKey(_ key: String, for provider: AIProviderChoice) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainError.emptyValue
        }

        let data = Data(trimmed.utf8)
        let account = account(for: provider)

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
            refreshFlags()
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
            refreshFlags()
            return
        }

        throw KeychainError.osStatus(updateStatus)
    }

    func deleteKey(for provider: AIProviderChoice) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider)
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }

        refreshFlags()
    }

    func savePrimaryProvider(_ provider: AIProviderChoice) {
        primaryProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "ai_primary_provider")
    }

    func sharedGeminiKey() -> String? {
        sharedKey(account: "shared_gemini_api_key")
    }

    func saveSharedGeminiKey(_ key: String) throws {
        try saveSharedKey(key, account: "shared_gemini_api_key")
        refreshFlags()
    }

    func deleteSharedGeminiKey() throws {
        try deleteSharedKey(account: "shared_gemini_api_key")
        refreshFlags()
    }

    func bundledGeminiKey() -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GEMINI_SHARED_API_KEY") as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func account(for provider: AIProviderChoice) -> String {
        switch provider {
        case .openAI:
            return "openai_api_key"
        case .gemini:
            return "gemini_api_key"
        }
    }

    private func sharedKey(account: String) -> String? {
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

    private func saveSharedKey(_ key: String, account: String) throws {
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
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
            return
        }

        throw KeychainError.osStatus(updateStatus)
    }

    private func deleteSharedKey(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
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
