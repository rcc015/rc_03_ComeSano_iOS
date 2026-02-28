import Foundation
import ComeSanoCore

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var today: DailyCalorieSnapshot?
    @Published public private(set) var weekly: WeeklyProgress?
    @Published public private(set) var errorMessage: String?

    private let burnProvider: DailyCalorieBurnProvider
    private let intakeProvider: DailyIntakeProvider
    private let profile: UserProfile
    private let calendar: Calendar

    public init(
        profile: UserProfile,
        burnProvider: DailyCalorieBurnProvider,
        intakeProvider: DailyIntakeProvider,
        calendar: Calendar = .current
    ) {
        self.profile = profile
        self.burnProvider = burnProvider
        self.intakeProvider = intakeProvider
        self.calendar = calendar
    }

    public func refresh(referenceDate: Date = .now) async {
        do {
            let consumed = try await intakeProvider.fetchConsumedCalories(for: referenceDate)
            let burned = try await burnProvider.fetchBurnedCalories(for: referenceDate)
            let todaySnapshot = DailyCalorieSnapshot(
                date: referenceDate,
                consumedKcal: consumed,
                activeBurnedKcal: burned.active,
                basalBurnedKcal: burned.basal,
                targetKcal: profile.dailyCalorieTarget
            )

            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? referenceDate
            let weeklyProgress = CalorieMath.weeklyProgress(from: [todaySnapshot], weekStart: startOfWeek)

            today = todaySnapshot
            weekly = weeklyProgress
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo leer la información de calorías: \(error.localizedDescription)"
        }
    }
}

public struct MockIntakeProvider: DailyIntakeProvider {
    private let kcal: Double

    public init(kcal: Double = 1850) {
        self.kcal = kcal
    }

    public func fetchConsumedCalories(for date: Date) async throws -> Double {
        _ = date
        return kcal
    }
}

public struct MockBurnProvider: DailyCalorieBurnProvider {
    private let active: Double
    private let basal: Double

    public init(active: Double = 520, basal: Double = 1450) {
        self.active = active
        self.basal = basal
    }

    public func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double) {
        _ = date
        return (active, basal)
    }
}
