import Foundation
import ComeSanoCore

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var today: DailyCalorieSnapshot?
    @Published public private(set) var weekly: WeeklyProgress?
    @Published public private(set) var weekSnapshots: [DailyCalorieSnapshot] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var currentGoal: PrimaryGoal

    private let burnProvider: DailyCalorieBurnProvider
    private let intakeProvider: DailyIntakeProvider
    private var profile: UserProfile
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
        self.currentGoal = profile.primaryGoal
    }

    public func refresh(referenceDate: Date = .now) async {
        do {
            let startOfWeek = startOfWeekMonday(for: referenceDate)
            let snapshots = try await makeWeekSnapshots(startOfWeek: startOfWeek)
            let weeklyProgress = CalorieMath.weeklyProgress(from: snapshots, weekStart: startOfWeek)
            let selectedDay = calendar.startOfDay(for: referenceDate)
            let todaySnapshot = snapshots.first { calendar.isDate($0.date, inSameDayAs: selectedDay) } ?? snapshots.last

            today = todaySnapshot
            weekly = weeklyProgress
            weekSnapshots = snapshots
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo leer la información de calorías: \(error.localizedDescription)"
        }
    }

    public func updateProfile(_ updatedProfile: UserProfile) {
        profile = updatedProfile
        currentGoal = updatedProfile.primaryGoal
    }

    private func startOfWeekMonday(for date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        // Sunday = 1 ... Saturday = 7 -> Monday-based offset (Mon=0 ... Sun=6)
        let mondayOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: startOfDay) ?? startOfDay
    }

    private func makeWeekSnapshots(startOfWeek: Date) async throws -> [DailyCalorieSnapshot] {
        var snapshots: [DailyCalorieSnapshot] = []
        snapshots.reserveCapacity(7)

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfWeek) else { continue }
            let consumed = try await intakeProvider.fetchConsumedCalories(for: day)
            let consumedMacros = try await fetchConsumedMacros(for: day)
            let burned = try await burnProvider.fetchBurnedCalories(for: day)
            snapshots.append(
                DailyCalorieSnapshot(
                    date: day,
                    consumedKcal: consumed,
                    activeBurnedKcal: burned.active,
                    basalBurnedKcal: burned.basal,
                    targetKcal: profile.dailyCalorieTarget,
                    consumedProteinGrams: consumedMacros.proteinGrams,
                    consumedCarbsGrams: consumedMacros.carbsGrams,
                    consumedFatGrams: consumedMacros.fatGrams
                )
            )
        }

        return snapshots
    }

    private func fetchConsumedMacros(for date: Date) async throws -> (proteinGrams: Double, carbsGrams: Double, fatGrams: Double) {
        guard let macroProvider = intakeProvider as? any DailyMacroIntakeProvider else {
            return (0, 0, 0)
        }
        return try await macroProvider.fetchConsumedMacros(for: date)
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
