import Foundation
import WatchConnectivity

@MainActor
final class WatchConnector: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchConnector()

    struct QuickAddFavoriteState: Codable, Equatable {
        let name: String
        let servingDescription: String
        let calories: Double
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let fiberGrams: Double
    }

    struct TodayMealState: Codable, Equatable {
        let label: String
        let name: String
        let servingDescription: String
        let calories: Double
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let fiberGrams: Double
        let scheduledHour: Int
        let scheduledMinute: Int
    }

    struct DashboardState: Equatable {
        let consumed: Double
        let goal: Double
        let totalBurned: Double
        let proteinActual: Double
        let proteinTarget: Double
        let carbsActual: Double
        let carbsTarget: Double
        let fatActual: Double
        let fatTarget: Double
        let fiberActual: Double
        let fiberTarget: Double
        let quickAddFavorites: [QuickAddFavoriteState]
        let todayMeals: [TodayMealState]
    }

    struct Event: Equatable {
        let alimento: String
        let servingDescription: String
        let calorias: Double
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let fiberGrams: Double
        let timestamp: Date
    }

    @Published private(set) var lastEvent: Event?
    @Published private(set) var caloriasRecientes: Double = 0
    @Published private(set) var dashboardState: DashboardState?
    var eventHandler: ((Event) -> Void)?

    private enum Keys {
        static let alimento = "alimento"
        static let servingDescription = "servingDescription"
        static let calorias = "calorias"
        static let proteinGrams = "proteinGrams"
        static let carbsGrams = "carbsGrams"
        static let fatGrams = "fatGrams"
        static let fiberGrams = "fiberGrams"
        static let timestamp = "timestamp"
        static let consumed = "dashboard.consumed"
        static let goal = "dashboard.goal"
        static let totalBurned = "dashboard.totalBurned"
        static let proteinActual = "dashboard.proteinActual"
        static let proteinTarget = "dashboard.proteinTarget"
        static let carbsActual = "dashboard.carbsActual"
        static let carbsTarget = "dashboard.carbsTarget"
        static let fatActual = "dashboard.fatActual"
        static let fatTarget = "dashboard.fatTarget"
        static let fiberActual = "dashboard.fiberActual"
        static let fiberTarget = "dashboard.fiberTarget"
        static let quickAddFavorites = "dashboard.quickAddFavorites"
        static let todayMeals = "dashboard.todayMeals"
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func registrarConsumo(
        alimento: String,
        calorias: Double,
        servingDescription: String = "",
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        fiberGrams: Double = 0
    ) {
        let payload: [String: Any] = [
            Keys.alimento: alimento,
            Keys.servingDescription: servingDescription,
            Keys.calorias: calorias,
            Keys.proteinGrams: proteinGrams,
            Keys.carbsGrams: carbsGrams,
            Keys.fatGrams: fatGrams,
            Keys.fiberGrams: fiberGrams,
            Keys.timestamp: Date().timeIntervalSince1970
        ]

        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("WatchConnector sendMessage error: \(error.localizedDescription)")
            }
        }
        session.transferUserInfo(payload)
    }

    func syncDashboardStateToWatch(
        consumed: Double,
        goal: Double,
        totalBurned: Double,
        proteinActual: Double,
        proteinTarget: Double,
        carbsActual: Double,
        carbsTarget: Double,
        fatActual: Double,
        fatTarget: Double,
        fiberActual: Double,
        fiberTarget: Double,
        quickAddFavorites: [QuickAddFavoriteState],
        todayMeals: [TodayMealState]
    ) {
        let encoder = JSONEncoder()
        guard
            let favoritesData = try? encoder.encode(quickAddFavorites),
            let todayMealsData = try? encoder.encode(todayMeals)
        else { return }

        let context: [String: Any] = [
            Keys.consumed: consumed,
            Keys.goal: goal,
            Keys.totalBurned: totalBurned,
            Keys.proteinActual: proteinActual,
            Keys.proteinTarget: proteinTarget,
            Keys.carbsActual: carbsActual,
            Keys.carbsTarget: carbsTarget,
            Keys.fatActual: fatActual,
            Keys.fatTarget: fatTarget,
            Keys.fiberActual: fiberActual,
            Keys.fiberTarget: fiberTarget,
            Keys.quickAddFavorites: favoritesData,
            Keys.todayMeals: todayMealsData
        ]

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("WatchConnector updateApplicationContext error: \(error.localizedDescription)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let parsed = Self.parsePayload(message)
        guard let parsed else { return }
        Task { @MainActor in
            self.applyParsedPayload(parsed)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let parsed = Self.parsePayload(userInfo)
        guard let parsed else { return }
        Task { @MainActor in
            self.applyParsedPayload(parsed)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        let parsed = Self.parseDashboardState(applicationContext)
        guard let parsed else { return }
        Task { @MainActor in
            self.dashboardState = parsed
        }
    }

    private nonisolated static func parsePayload(_ datos: [String: Any]) -> (alimento: String, servingDescription: String, calorias: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double, fiberGrams: Double, timestamp: Date)? {
        guard let alimento = datos[Keys.alimento] as? String else { return nil }
        let servingDescription = (datos[Keys.servingDescription] as? String) ?? ""

        let calorias: Double
        if let value = datos[Keys.calorias] as? Double {
            calorias = value
        } else if let number = datos[Keys.calorias] as? NSNumber {
            calorias = number.doubleValue
        } else {
            return nil
        }

        let proteinGrams = (datos[Keys.proteinGrams] as? NSNumber)?.doubleValue ?? (datos[Keys.proteinGrams] as? Double) ?? 0
        let carbsGrams = (datos[Keys.carbsGrams] as? NSNumber)?.doubleValue ?? (datos[Keys.carbsGrams] as? Double) ?? 0
        let fatGrams = (datos[Keys.fatGrams] as? NSNumber)?.doubleValue ?? (datos[Keys.fatGrams] as? Double) ?? 0
        let fiberGrams = (datos[Keys.fiberGrams] as? NSNumber)?.doubleValue ?? (datos[Keys.fiberGrams] as? Double) ?? 0

        let timestamp: Date
        if let raw = datos[Keys.timestamp] as? Double {
            timestamp = Date(timeIntervalSince1970: raw)
        } else if let number = datos[Keys.timestamp] as? NSNumber {
            timestamp = Date(timeIntervalSince1970: number.doubleValue)
        } else {
            timestamp = .now
        }

        return (alimento, servingDescription, calorias, proteinGrams, carbsGrams, fatGrams, fiberGrams, timestamp)
    }

    private nonisolated static func parseDashboardState(_ data: [String: Any]) -> DashboardState? {
        let consumed: Double
        if let value = data[Keys.consumed] as? Double {
            consumed = value
        } else if let number = data[Keys.consumed] as? NSNumber {
            consumed = number.doubleValue
        } else {
            return nil
        }

        let goal: Double
        if let value = data[Keys.goal] as? Double {
            goal = value
        } else if let number = data[Keys.goal] as? NSNumber {
            goal = number.doubleValue
        } else {
            return nil
        }

        let totalBurned: Double
        if let value = data[Keys.totalBurned] as? Double {
            totalBurned = value
        } else if let number = data[Keys.totalBurned] as? NSNumber {
            totalBurned = number.doubleValue
        } else {
            totalBurned = 0
        }

        let proteinActual = (data[Keys.proteinActual] as? NSNumber)?.doubleValue ?? (data[Keys.proteinActual] as? Double) ?? 0
        let proteinTarget = (data[Keys.proteinTarget] as? NSNumber)?.doubleValue ?? (data[Keys.proteinTarget] as? Double) ?? 0
        let carbsActual = (data[Keys.carbsActual] as? NSNumber)?.doubleValue ?? (data[Keys.carbsActual] as? Double) ?? 0
        let carbsTarget = (data[Keys.carbsTarget] as? NSNumber)?.doubleValue ?? (data[Keys.carbsTarget] as? Double) ?? 0
        let fatActual = (data[Keys.fatActual] as? NSNumber)?.doubleValue ?? (data[Keys.fatActual] as? Double) ?? 0
        let fatTarget = (data[Keys.fatTarget] as? NSNumber)?.doubleValue ?? (data[Keys.fatTarget] as? Double) ?? 0
        let fiberActual = (data[Keys.fiberActual] as? NSNumber)?.doubleValue ?? (data[Keys.fiberActual] as? Double) ?? 0
        let fiberTarget = (data[Keys.fiberTarget] as? NSNumber)?.doubleValue ?? (data[Keys.fiberTarget] as? Double) ?? 0

        let decoder = JSONDecoder()
        let quickAddFavorites: [QuickAddFavoriteState]
        if let favoritesData = data[Keys.quickAddFavorites] as? Data,
           let decoded = try? decoder.decode([QuickAddFavoriteState].self, from: favoritesData) {
            quickAddFavorites = decoded
        } else {
            quickAddFavorites = []
        }

        let todayMeals: [TodayMealState]
        if let todayMealsData = data[Keys.todayMeals] as? Data,
           let decoded = try? decoder.decode([TodayMealState].self, from: todayMealsData) {
            todayMeals = decoded
        } else {
            todayMeals = []
        }

        return DashboardState(
            consumed: consumed,
            goal: goal,
            totalBurned: totalBurned,
            proteinActual: proteinActual,
            proteinTarget: proteinTarget,
            carbsActual: carbsActual,
            carbsTarget: carbsTarget,
            fatActual: fatActual,
            fatTarget: fatTarget,
            fiberActual: fiberActual,
            fiberTarget: fiberTarget,
            quickAddFavorites: quickAddFavorites,
            todayMeals: todayMeals
        )
    }

    private func applyParsedPayload(_ payload: (alimento: String, servingDescription: String, calorias: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double, fiberGrams: Double, timestamp: Date)) {
        caloriasRecientes += payload.calorias
        let event = Event(
            alimento: payload.alimento,
            servingDescription: payload.servingDescription,
            calorias: payload.calorias,
            proteinGrams: payload.proteinGrams,
            carbsGrams: payload.carbsGrams,
            fatGrams: payload.fatGrams,
            fiberGrams: payload.fiberGrams,
            timestamp: payload.timestamp
        )
        lastEvent = event
        eventHandler?(event)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
