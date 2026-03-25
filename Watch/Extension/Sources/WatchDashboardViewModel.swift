import Foundation
import ComeSanoHealthKit
import WidgetKit

#if canImport(WatchKit)
import WatchKit
#endif

@MainActor
final class WatchDashboardViewModel: ObservableObject {
    struct QuickAddFavorite: Codable, Identifiable, Hashable {
        var id: String { name + "|" + servingDescription }
        let name: String
        let servingDescription: String
        let calories: Double
        let proteinGrams: Double
        let carbsGrams: Double
        let fatGrams: Double
        let fiberGrams: Double
    }

    struct TodayMeal: Codable, Identifiable, Hashable {
        var id: String { label + "|" + name }
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

        var scheduledTimeText: String {
            String(format: "%02d:%02d", scheduledHour, scheduledMinute)
        }
    }

    @Published private(set) var consumed: Double = 0
    @Published private(set) var totalBurned: Double = 0
    @Published var goal: Double = 2100
    @Published private(set) var proteinActual: Double = 0
    @Published private(set) var proteinTarget: Double = 0
    @Published private(set) var carbsActual: Double = 0
    @Published private(set) var carbsTarget: Double = 0
    @Published private(set) var fatActual: Double = 0
    @Published private(set) var fatTarget: Double = 0
    @Published private(set) var fiberActual: Double = 0
    @Published private(set) var fiberTarget: Double = 0
    @Published private(set) var quickAddFavorites: [QuickAddFavorite] = []
    @Published private(set) var todayMeals: [TodayMeal] = []
    @Published private(set) var statusMessage: String?

    private let healthStore: HealthKitNutritionStore
    private let widgetStore = WatchWidgetStore()
    private let connector = WatchConnector.shared
    private var allTodayMeals: [TodayMeal] = []

    init(healthStore: HealthKitNutritionStore = HealthKitNutritionStore()) {
        self.healthStore = healthStore
    }

    var ringProgress: Double {
        let safeGoal = max(goal, 1)
        return max(0, min(consumed / safeGoal, 1))
    }

    private func boundedProgress(actual: Double, target: Double) -> Double {
        let safeTarget = max(target, 1)
        return max(0, min(actual / safeTarget, 1))
    }

    var proteinProgress: Double {
        boundedProgress(actual: proteinActual, target: proteinTarget)
    }

    var carbsProgress: Double {
        boundedProgress(actual: carbsActual, target: carbsTarget)
    }

    var fatProgress: Double {
        boundedProgress(actual: fatActual, target: fatTarget)
    }

    var fiberProgress: Double {
        boundedProgress(actual: fiberActual, target: fiberTarget)
    }

    func requestAuthorizationAndRefresh() async {
        do {
            try await healthStore.requestAuthorization()
            await refresh()
        } catch {
            await refresh()
            if connector.dashboardState == nil {
                statusMessage = "Permiso de HealthKit no disponible."
            }
        }
    }

    func refresh() async {
        if applyRemoteStateIfAvailable() {
            widgetStore.save(consumed: consumed, goal: goal)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        loadSharedState()
        do {
            async let consumedValue = healthStore.fetchConsumedCalories(for: .now)
            async let burnedValue = healthStore.fetchBurnedCalories(for: .now)
            let (newConsumed, burned) = try await (consumedValue, burnedValue)
            consumed = newConsumed
            totalBurned = burned.active + burned.basal
            widgetStore.save(consumed: consumed, goal: goal)
            WidgetCenter.shared.reloadAllTimelines()
            statusMessage = nil
        } catch {
            statusMessage = "No se pudo leer progreso."
        }
    }

    @discardableResult
    func applyRemoteStateIfAvailable() -> Bool {
        guard let remoteState = connector.dashboardState else { return false }
        consumed = remoteState.consumed
        goal = remoteState.goal
        totalBurned = remoteState.totalBurned
        proteinActual = remoteState.proteinActual
        proteinTarget = remoteState.proteinTarget
        carbsActual = remoteState.carbsActual
        carbsTarget = remoteState.carbsTarget
        fatActual = remoteState.fatActual
        fatTarget = remoteState.fatTarget
        fiberActual = remoteState.fiberActual
        fiberTarget = remoteState.fiberTarget
        quickAddFavorites = remoteState.quickAddFavorites.map {
            QuickAddFavorite(
                name: $0.name,
                servingDescription: $0.servingDescription,
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams,
                fiberGrams: $0.fiberGrams
            )
        }
        allTodayMeals = remoteState.todayMeals.map {
            TodayMeal(
                label: $0.label,
                name: $0.name,
                servingDescription: $0.servingDescription,
                calories: $0.calories,
                proteinGrams: $0.proteinGrams,
                carbsGrams: $0.carbsGrams,
                fatGrams: $0.fatGrams,
                fiberGrams: $0.fiberGrams,
                scheduledHour: $0.scheduledHour,
                scheduledMinute: $0.scheduledMinute
            )
        }
        refreshSuggestedMeals()
        statusMessage = nil
        return true
    }

    func registerCoffee() async {
        connector.registrarConsumo(
            alimento: "Café con leche deslactosada y Splenda",
            calorias: 45,
            servingDescription: "250 ml",
            proteinGrams: 2.5,
            carbsGrams: 4,
            fatGrams: 1.5,
            fiberGrams: 0
        )
        applyLocalConsumption(calories: 45, protein: 2.5, carbs: 4, fat: 1.5, fiber: 0)
        do {
            try await healthStore.saveDietaryEnergy(kilocalories: 45, at: .now)
            statusMessage = "Café registrado"
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
        } catch {
            statusMessage = "Café enviado al iPhone"
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await refresh()
    }

    func registerWater() async {
        connector.registrarConsumo(
            alimento: "Vaso de agua",
            calorias: 0,
            servingDescription: "250 ml"
        )
        statusMessage = "Agua registrada"
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
        await refresh()
    }

    func registerFavorite(_ favorite: QuickAddFavorite) async {
        connector.registrarConsumo(
            alimento: favorite.name,
            calorias: favorite.calories,
            servingDescription: favorite.servingDescription,
            proteinGrams: favorite.proteinGrams,
            carbsGrams: favorite.carbsGrams,
            fatGrams: favorite.fatGrams,
            fiberGrams: favorite.fiberGrams
        )
        applyLocalConsumption(
            calories: favorite.calories,
            protein: favorite.proteinGrams,
            carbs: favorite.carbsGrams,
            fat: favorite.fatGrams,
            fiber: favorite.fiberGrams
        )
        do {
            if favorite.calories > 0 {
                try await healthStore.saveDietaryEnergy(kilocalories: favorite.calories, at: .now)
            }
            statusMessage = "\(favorite.name) registrado"
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
        } catch {
            statusMessage = "\(favorite.name) enviado al iPhone"
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await refresh()
    }

    func registerTodayMeal(_ meal: TodayMeal) async {
        connector.registrarConsumo(
            alimento: meal.name,
            calorias: meal.calories,
            servingDescription: meal.servingDescription,
            proteinGrams: meal.proteinGrams,
            carbsGrams: meal.carbsGrams,
            fatGrams: meal.fatGrams,
            fiberGrams: meal.fiberGrams
        )
        applyLocalConsumption(
            calories: meal.calories,
            protein: meal.proteinGrams,
            carbs: meal.carbsGrams,
            fat: meal.fatGrams,
            fiber: meal.fiberGrams
        )
        do {
            if meal.calories > 0 {
                try await healthStore.saveDietaryEnergy(kilocalories: meal.calories, at: .now)
            }
            statusMessage = "\(meal.label) registrada"
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
        } catch {
            statusMessage = "\(meal.label) enviada al iPhone"
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        await refresh()
    }

    private func loadSharedState() {
        goal = widgetStore.loadGoal(default: goal)
        quickAddFavorites = widgetStore.loadFavorites()
        allTodayMeals = widgetStore.loadTodayMeals()
        refreshSuggestedMeals()
    }

    private func applyLocalConsumption(calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double) {
        consumed += calories
        proteinActual += protein
        carbsActual += carbs
        fatActual += fat
        fiberActual += fiber
        widgetStore.save(consumed: consumed, goal: goal)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshSuggestedMeals(referenceDate: Date = .now) {
        todayMeals = suggestedMeals(from: allTodayMeals, referenceDate: referenceDate)
    }

    private func suggestedMeals(from meals: [TodayMeal], referenceDate: Date) -> [TodayMeal] {
        guard !meals.isEmpty else { return [] }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: referenceDate)
        if currentHour < 7 {
            return []
        }

        let sortedMeals = meals.sorted {
            ($0.scheduledHour, $0.scheduledMinute) < ($1.scheduledHour, $1.scheduledMinute)
        }

        let anchorIndex = sortedMeals.firstIndex { meal in
            guard let scheduledDate = calendar.date(
                bySettingHour: meal.scheduledHour,
                minute: meal.scheduledMinute,
                second: 0,
                of: referenceDate
            ) else {
                return false
            }

            let visibleStart = scheduledDate.addingTimeInterval(-3600)
            let visibleEnd = scheduledDate.addingTimeInterval(3600)
            return referenceDate >= visibleStart && referenceDate <= visibleEnd
        }

        guard let anchorIndex else { return [] }
        return Array(sortedMeals[anchorIndex...].prefix(3))
    }
}

private struct WatchWidgetStore {
    private let defaults = UserDefaults(suiteName: "group.rcTools.ComeSano")
    private enum Keys {
        static let consumed = "widget.calories.consumed"
        static let goal = "widget.calories.goal"
        static let watchQuickAddFavorites = "watch.quickAddFavorites"
        static let watchTodayMeals = "watch.todayMeals"
    }

    func save(consumed: Double, goal: Double) {
        defaults?.set(consumed, forKey: Keys.consumed)
        defaults?.set(goal, forKey: Keys.goal)
    }

    func loadGoal(default defaultValue: Double) -> Double {
        let stored = defaults?.double(forKey: Keys.goal) ?? defaultValue
        return stored > 0 ? stored : defaultValue
    }

    func loadFavorites() -> [WatchDashboardViewModel.QuickAddFavorite] {
        guard let data = defaults?.data(forKey: Keys.watchQuickAddFavorites) else { return [] }
        return (try? JSONDecoder().decode([WatchDashboardViewModel.QuickAddFavorite].self, from: data)) ?? []
    }

    func loadTodayMeals() -> [WatchDashboardViewModel.TodayMeal] {
        guard let data = defaults?.data(forKey: Keys.watchTodayMeals) else { return [] }
        return (try? JSONDecoder().decode([WatchDashboardViewModel.TodayMeal].self, from: data)) ?? []
    }
}
