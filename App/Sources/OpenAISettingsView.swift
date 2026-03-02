import SwiftUI
import ComeSanoAI
import UserNotifications
#if os(iOS)
import UIKit
#endif

struct AISettingsView: View {
    @ObservedObject var keychainStore: AIKeychainStore
    @ObservedObject var reminderManager: ReminderNotificationManager
    @ObservedObject var mealScheduleStore: MealScheduleStore
    let onConfigurationChanged: () -> Void
    let onOpenDietaryProfile: () -> Void

    @State private var openAIKeyInput = ""
    @State private var geminiKeyInput = ""
    @State private var statusMessage: String?
    @State private var reminderStatusMessage: String?

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

                Section("Plan Nutricional") {
                    Button("Editar cuestionario y meta diaria") {
                        onOpenDietaryProfile()
                    }
                }

                Section("Horarios de consumo (Plan)") {
                    timePickerRow(
                        title: "Desayuno",
                        hour: $mealScheduleStore.breakfastHour,
                        minute: $mealScheduleStore.breakfastMinute
                    )
                    timePickerRow(
                        title: "Colación 1",
                        hour: $mealScheduleStore.snack1Hour,
                        minute: $mealScheduleStore.snack1Minute
                    )
                    timePickerRow(
                        title: "Comida",
                        hour: $mealScheduleStore.lunchHour,
                        minute: $mealScheduleStore.lunchMinute
                    )
                    timePickerRow(
                        title: "Colación 2",
                        hour: $mealScheduleStore.snack2Hour,
                        minute: $mealScheduleStore.snack2Minute
                    )
                    timePickerRow(
                        title: "Cena",
                        hour: $mealScheduleStore.dinnerHour,
                        minute: $mealScheduleStore.dinnerMinute
                    )

                    Button("Guardar horarios") {
                        mealScheduleStore.save()
                        reminderStatusMessage = "Horarios de plan guardados."
                    }

                    Button("Restablecer horarios por default", role: .destructive) {
                        mealScheduleStore.resetDefaults()
                        reminderStatusMessage = "Horarios restablecidos."
                    }
                }

                Section("Recordatorios") {
                    Text("Permiso: \(notificationPermissionText(reminderManager.authorizationStatus))")
                        .foregroundStyle(.secondary)

                    #if os(iOS)
                    if reminderManager.authorizationStatus == .denied {
                        Button("Abrir Ajustes de iOS") {
                            openSystemSettings()
                        }
                    }
                    #endif

                    Toggle("Agua cada cierto tiempo", isOn: $reminderManager.waterReminderEnabled)
                    Stepper("Intervalo agua: \(reminderManager.waterIntervalHours)h", value: $reminderManager.waterIntervalHours, in: 1...8)
                        .disabled(!reminderManager.waterReminderEnabled)

                    Toggle("Comida diaria", isOn: $reminderManager.mealReminderEnabled)

                    DatePicker(
                        "Hora de comida",
                        selection: Binding(
                            get: { mealDateFromStoredTime() },
                            set: { newValue in
                                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                reminderManager.mealHour = components.hour ?? 14
                                reminderManager.mealMinute = components.minute ?? 0
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!reminderManager.mealReminderEnabled)

                    Toggle("Plan completo (desayuno, colaciones, comida y cena)", isOn: $reminderManager.nutritionPlanRemindersEnabled)

                    Button("Aplicar recordatorios") {
                        Task {
                            await reminderManager.applyCurrentSchedule(mealSchedule: mealScheduleStore)
                            reminderStatusMessage = "Recordatorios actualizados."
                        }
                    }

                    Button("Desactivar todos", role: .destructive) {
                        reminderManager.clearAllReminders()
                        reminderStatusMessage = "Recordatorios desactivados."
                    }

                    HStack {
                        Text("Vasos marcados desde notificación")
                        Spacer()
                        Text("\(reminderManager.loggedWaterGlasses)")
                            .fontWeight(.semibold)
                    }

                    Button("Reiniciar contador de agua", role: .destructive) {
                        reminderManager.resetHydrationCounter()
                    }

                    if let reminderStatusMessage {
                        Text(reminderStatusMessage)
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
                Task {
                    await reminderManager.refreshAuthorizationStatus()
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

    private func mealDateFromStoredTime() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = reminderManager.mealHour
        components.minute = reminderManager.mealMinute
        return Calendar.current.date(from: components) ?? .now
    }

    private func notificationPermissionText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "autorizado"
        case .denied:
            return "denegado (actívalo en Ajustes de iOS)"
        case .notDetermined:
            return "pendiente"
        @unknown default:
            return "desconocido"
        }
    }

    #if os(iOS)
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
    #endif

    @ViewBuilder
    private func timePickerRow(title: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: {
                    makeDate(hour: hour.wrappedValue, minute: minute.wrappedValue)
                },
                set: { newValue in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    hour.wrappedValue = components.hour ?? hour.wrappedValue
                    minute.wrappedValue = components.minute ?? minute.wrappedValue
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }
}
