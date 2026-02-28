import Foundation

public struct DailyCalorieSnapshot: Sendable {
    public var date: Date
    public var consumedKcal: Double
    public var activeBurnedKcal: Double
    public var basalBurnedKcal: Double
    public var targetKcal: Double

    public init(
        date: Date,
        consumedKcal: Double,
        activeBurnedKcal: Double,
        basalBurnedKcal: Double,
        targetKcal: Double
    ) {
        self.date = date
        self.consumedKcal = consumedKcal
        self.activeBurnedKcal = activeBurnedKcal
        self.basalBurnedKcal = basalBurnedKcal
        self.targetKcal = targetKcal
    }

    public var totalBurnedKcal: Double { activeBurnedKcal + basalBurnedKcal }
    public var netKcal: Double { consumedKcal - totalBurnedKcal }
    public var targetDeltaKcal: Double { consumedKcal - targetKcal }
}
