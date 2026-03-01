import Foundation
import UserNotifications

@MainActor
final class ReminderNotificationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var waterReminderEnabled: Bool
    @Published var mealReminderEnabled: Bool
    @Published var waterIntervalHours: Int
    @Published var mealHour: Int
    @Published var mealMinute: Int
    @Published private(set) var loggedWaterGlasses: Int

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    private enum Keys {
        static let waterEnabled = "notifications.water.enabled"
        static let mealEnabled = "notifications.meal.enabled"
        static let waterIntervalHours = "notifications.water.intervalHours"
        static let mealHour = "notifications.meal.hour"
        static let mealMinute = "notifications.meal.minute"
        static let loggedWaterGlasses = "notifications.water.loggedCount"
    }

    enum IDs {
        static let categoryHydration = "HYDRATION_CATEGORY"
        static let actionWaterGlassDone = "ACTION_WATER_GLASS_DONE"
        static let waterRequest = "water_every_x_hours"
        static let mealRequest = "meal_daily_time"
    }

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults

        let storedInterval = defaults.integer(forKey: Keys.waterIntervalHours)
        let safeInterval = (1...8).contains(storedInterval) ? storedInterval : 2
        let storedHour = defaults.object(forKey: Keys.mealHour) as? Int ?? 14
        let storedMinute = defaults.object(forKey: Keys.mealMinute) as? Int ?? 0

        self.waterReminderEnabled = defaults.bool(forKey: Keys.waterEnabled)
        self.mealReminderEnabled = defaults.bool(forKey: Keys.mealEnabled)
        self.waterIntervalHours = safeInterval
        self.mealHour = max(0, min(23, storedHour))
        self.mealMinute = max(0, min(59, storedMinute))
        self.loggedWaterGlasses = defaults.integer(forKey: Keys.loggedWaterGlasses)

        super.init()
        center.delegate = self
        registerCategories()

        Task {
            await refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func applyCurrentSchedule() async {
        persistSettings()

        guard await requestAuthorizationIfNeeded() else {
            waterReminderEnabled = false
            mealReminderEnabled = false
            persistSettings()
            return
        }

        if waterReminderEnabled {
            await scheduleWaterReminder(everyHours: waterIntervalHours)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [IDs.waterRequest])
        }

        if mealReminderEnabled {
            await scheduleMealReminder(hour: mealHour, minute: mealMinute)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [IDs.mealRequest])
        }
    }

    func clearAllReminders() {
        waterReminderEnabled = false
        mealReminderEnabled = false
        persistSettings()
        center.removePendingNotificationRequests(withIdentifiers: [IDs.waterRequest, IDs.mealRequest])
    }

    func resetHydrationCounter() {
        loggedWaterGlasses = 0
        defaults.set(0, forKey: Keys.loggedWaterGlasses)
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshAuthorizationStatus()
                return granted
            } catch {
                await refreshAuthorizationStatus()
                return false
            }
        @unknown default:
            return false
        }
    }

    private func scheduleWaterReminder(everyHours hours: Int) async {
        let safeHours = max(1, min(8, hours))
        let content = UNMutableNotificationContent()
        content.title = "Hora de hidratarte"
        content.body = "Toma agua para mantener tu progreso."
        content.sound = .default
        content.categoryIdentifier = IDs.categoryHydration

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(safeHours * 3600), repeats: true)
        let request = UNNotificationRequest(identifier: IDs.waterRequest, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [IDs.waterRequest])
        try? await center.add(request)
    }

    private func scheduleMealReminder(hour: Int, minute: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Hora de tu comida"
        content.body = "Registra tu comida para mantener tus macros al día."
        content.sound = .default

        var components = DateComponents()
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: IDs.mealRequest, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [IDs.mealRequest])
        try? await center.add(request)
    }

    private func persistSettings() {
        defaults.set(waterReminderEnabled, forKey: Keys.waterEnabled)
        defaults.set(mealReminderEnabled, forKey: Keys.mealEnabled)
        defaults.set(waterIntervalHours, forKey: Keys.waterIntervalHours)
        defaults.set(mealHour, forKey: Keys.mealHour)
        defaults.set(mealMinute, forKey: Keys.mealMinute)
    }

    private func registerCategories() {
        let waterAction = UNNotificationAction(
            identifier: IDs.actionWaterGlassDone,
            title: "Tomé 1 vaso",
            options: []
        )
        let hydrationCategory = UNNotificationCategory(
            identifier: IDs.categoryHydration,
            actions: [waterAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([hydrationCategory])
    }

    private func handleNotificationAction(_ identifier: String) {
        guard identifier == IDs.actionWaterGlassDone else { return }
        loggedWaterGlasses += 1
        defaults.set(loggedWaterGlasses, forKey: Keys.loggedWaterGlasses)
    }
}

extension ReminderNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        await MainActor.run {
            handleNotificationAction(actionIdentifier)
        }
    }
}
