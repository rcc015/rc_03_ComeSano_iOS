import SwiftUI
import ComeSanoAI

struct AISettingsView: View {
    @ObservedObject var keychainStore: AIKeychainStore
    let onConfigurationChanged: () -> Void

    @State private var openAIKeyInput = ""
    @State private var geminiKeyInput = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Proveedor principal") {
                    Picker("Proveedor", selection: Binding(
                        get: { keychainStore.primaryProvider },
                        set: { newValue in
                            keychainStore.savePrimaryProvider(newValue)
                            onConfigurationChanged()
                        }
                    )) {
                        Text("OpenAI").tag(AIProviderChoice.openAI)
                        Text("Gemini").tag(AIProviderChoice.gemini)
                    }
                    .pickerStyle(.segmented)
                }

                Section("OpenAI API Key") {
                    SecureField("sk-...", text: $openAIKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Guardar OpenAI") {
                        saveKey(openAIKeyInput, provider: .openAI)
                    }

                    Button("Eliminar OpenAI", role: .destructive) {
                        deleteKey(provider: .openAI)
                    }
                    .disabled(!keychainStore.hasOpenAIKey)
                }

                Section("Gemini API Key") {
                    SecureField("AIza...", text: $geminiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Guardar Gemini") {
                        saveKey(geminiKeyInput, provider: .gemini)
                    }

                    Button("Eliminar Gemini", role: .destructive) {
                        deleteKey(provider: .gemini)
                    }
                    .disabled(!keychainStore.hasGeminiKey)
                }

                Section("Estado") {
                    Text("OpenAI: \(keychainStore.hasOpenAIKey ? "configurada" : "sin key")")
                    Text("Gemini: \(keychainStore.hasGeminiKey ? "configurada" : "sin key")")
                    if let statusMessage {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Configuración IA")
            .onAppear {
                if openAIKeyInput.isEmpty, let existing = keychainStore.key(for: .openAI) {
                    openAIKeyInput = existing
                }
                if geminiKeyInput.isEmpty, let existing = keychainStore.key(for: .gemini) {
                    geminiKeyInput = existing
                }
            }
        }
    }

    private func saveKey(_ value: String, provider: AIProviderChoice) {
        do {
            try keychainStore.saveKey(value, for: provider)
            onConfigurationChanged()
            statusMessage = "API key de \(provider == .openAI ? "OpenAI" : "Gemini") guardada correctamente."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func deleteKey(provider: AIProviderChoice) {
        do {
            try keychainStore.deleteKey(for: provider)
            if provider == .openAI { openAIKeyInput = "" } else { geminiKeyInput = "" }
            onConfigurationChanged()
            statusMessage = "API key eliminada."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
