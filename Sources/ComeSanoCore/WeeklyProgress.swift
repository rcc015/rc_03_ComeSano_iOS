import Foundation

public struct WeeklyProgress: Sendable {
    public var weekStart: Date
    public var averageNetKcal: Double
    public var averageTargetDeltaKcal: Double
    public var adherenceScore: Double

    public init(
        weekStart: Date,
        averageNetKcal: Double,
        averageTargetDeltaKcal: Double,
        adherenceScore: Double
    ) {
        self.weekStart = weekStart
        self.averageNetKcal = averageNetKcal
        self.averageTargetDeltaKcal = averageTargetDeltaKcal
        self.adherenceScore = adherenceScore
    }
}
