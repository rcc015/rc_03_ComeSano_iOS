import Foundation

public protocol DailyCalorieBurnProvider: Sendable {
    func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double)
}

public protocol DailyIntakeProvider: Sendable {
    func fetchConsumedCalories(for date: Date) async throws -> Double
}
