import Foundation
import ComeSanoHealthKit
import WidgetKit

#if canImport(WatchKit)
import WatchKit
#endif

@MainActor
final class WatchDashboardViewModel: ObservableObject {
    @Published private(set) var consumed: Double = 0
    @Published private(set) var totalBurned: Double = 0
    @Published var goal: Double = 2100
    @Published private(set) var statusMessage: String?

    private let healthStore: HealthKitNutritionStore
    private let widgetStore = WatchWidgetStore()
    private let connector = WatchConnector.shared

    init(healthStore: HealthKitNutritionStore = HealthKitNutritionStore()) {
        self.healthStore = healthStore
    }

    var ringProgress: Double {
        let safeGoal = max(goal, 1)
        return max(0, min(consumed / safeGoal, 1))
    }

    func requestAuthorizationAndRefresh() async {
        do {
            try await healthStore.requestAuthorization()
            await refresh()
        } catch {
            statusMessage = "Permiso de HealthKit no disponible."
        }
    }

    func refresh() async {
        do {
            async let consumedValue = healthStore.fetchConsumedCalories(for: .now)
            async let burnedValue = healthStore.fetchBurnedCalories(for: .now)
            let (newConsumed, burned) = try await (consumedValue, burnedValue)
            consumed = newConsumed
            totalBurned = burned.active + burned.basal
            widgetStore.save(consumed: consumed, goal: goal)
            WidgetCenter.shared.reloadTimelines(ofKind: "CalorieWidget")
            statusMessage = nil
        } catch {
            statusMessage = "No se pudo leer progreso."
        }
    }

    func registerCoffee() async {
        do {
            try await healthStore.saveDietaryEnergy(kilocalories: 45, at: .now)
            connector.registrarConsumo(alimento: "Café con leche deslactosada y Splenda", calorias: 45)
            statusMessage = "Café registrado"
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.success)
            #endif
            await refresh()
        } catch {
            statusMessage = "No se pudo registrar café."
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.failure)
            #endif
        }
    }

    func registerWater() async {
        statusMessage = "Agua registrada"
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}

private struct WatchWidgetStore {
    private let defaults = UserDefaults(suiteName: "group.rcTools.ComeSano")

    func save(consumed: Double, goal: Double) {
        defaults?.set(consumed, forKey: "widget.calories.consumed")
        defaults?.set(goal, forKey: "widget.calories.goal")
    }
}
