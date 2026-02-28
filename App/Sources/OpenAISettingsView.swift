import SwiftUI

struct OpenAISettingsView: View {
    @ObservedObject var keychainStore: OpenAIKeychainStore
    let onKeyChanged: (String?) -> Void

    @State private var keyInput = ""
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API Key") {
                    SecureField("sk-...", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Guardar en Keychain") {
                        saveKey()
                    }

                    Button("Eliminar de Keychain", role: .destructive) {
                        deleteKey()
                    }
                    .disabled(!keychainStore.hasStoredKey)
                }

                Section("Estado") {
                    Text(keychainStore.hasStoredKey ? "API key guardada" : "No hay API key guardada")
                    if let statusMessage {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Configuración IA")
            .onAppear {
                if keyInput.isEmpty, let existing = keychainStore.currentKey() {
                    keyInput = existing
                }
            }
        }
    }

    private func saveKey() {
        do {
            try keychainStore.saveKey(keyInput)
            onKeyChanged(keychainStore.currentKey())
            statusMessage = "API key guardada correctamente."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func deleteKey() {
        do {
            try keychainStore.deleteKey()
            keyInput = ""
            onKeyChanged(nil)
            statusMessage = "API key eliminada."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
