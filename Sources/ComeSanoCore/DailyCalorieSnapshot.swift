import Foundation

public struct DailyCalorieSnapshot: Sendable {
    public var date: Date
    public var consumedKcal: Double
    public var activeBurnedKcal: Double
    public var basalBurnedKcal: Double
    public var targetKcal: Double
    public var consumedProteinGrams: Double
    public var consumedCarbsGrams: Double
    public var consumedFatGrams: Double

    public init(
        date: Date,
        consumedKcal: Double,
        activeBurnedKcal: Double,
        basalBurnedKcal: Double,
        targetKcal: Double,
        consumedProteinGrams: Double = 0,
        consumedCarbsGrams: Double = 0,
        consumedFatGrams: Double = 0
    ) {
        self.date = date
        self.consumedKcal = consumedKcal
        self.activeBurnedKcal = activeBurnedKcal
        self.basalBurnedKcal = basalBurnedKcal
        self.targetKcal = targetKcal
        self.consumedProteinGrams = consumedProteinGrams
        self.consumedCarbsGrams = consumedCarbsGrams
        self.consumedFatGrams = consumedFatGrams
    }

    public var totalBurnedKcal: Double { activeBurnedKcal + basalBurnedKcal }
    public var netKcal: Double { consumedKcal - totalBurnedKcal }
    public var targetDeltaKcal: Double { consumedKcal - targetKcal }
    public var dailyAdherenceScore: Double { max(0, 100 - abs(netKcal) / 10) }
}
