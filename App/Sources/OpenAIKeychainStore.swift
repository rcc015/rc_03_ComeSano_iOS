import Foundation
import Security
import ComeSanoAI

@MainActor
final class AIKeychainStore: ObservableObject {
    @Published private(set) var hasOpenAIKey = false
    @Published private(set) var hasGeminiKey = false
    @Published var primaryProvider: AIProviderChoice

    private let service: String

    init(service: String = "rcTools.ComeSano") {
        self.service = service

        let savedProviderRaw = UserDefaults.standard.string(forKey: "ai_primary_provider")
        self.primaryProvider = AIProviderChoice(rawValue: savedProviderRaw ?? "openAI") ?? .openAI

        refreshFlags()
    }

    func refreshFlags() {
        hasOpenAIKey = key(for: .openAI) != nil
        hasGeminiKey = key(for: .gemini) != nil
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

    private func account(for provider: AIProviderChoice) -> String {
        switch provider {
        case .openAI:
            return "openai_api_key"
        case .gemini:
            return "gemini_api_key"
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
