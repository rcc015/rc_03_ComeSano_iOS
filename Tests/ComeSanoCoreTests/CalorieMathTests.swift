import XCTest
@testable import ComeSanoCore

final class CalorieMathTests: XCTestCase {
    func testWeeklyProgressUsesAverages() {
        let snapshots = [
            DailyCalorieSnapshot(date: .now, consumedKcal: 2000, activeBurnedKcal: 400, basalBurnedKcal: 1400, targetKcal: 2100),
            DailyCalorieSnapshot(date: .now, consumedKcal: 2200, activeBurnedKcal: 500, basalBurnedKcal: 1400, targetKcal: 2100)
        ]

        let result = CalorieMath.weeklyProgress(from: snapshots, weekStart: .now)

        XCTAssertEqual(result.averageNetKcal, 250, accuracy: 0.001)
        XCTAssertEqual(result.averageTargetDeltaKcal, 0, accuracy: 0.001)
        XCTAssertEqual(result.adherenceScore, 100, accuracy: 0.001)
    }

    func testWeeklyProgressDropsAdherenceWhenFarFromTarget() {
        let snapshots = [
            DailyCalorieSnapshot(date: .now, consumedKcal: 3000, activeBurnedKcal: 200, basalBurnedKcal: 1300, targetKcal: 2000)
        ]

        let result = CalorieMath.weeklyProgress(from: snapshots, weekStart: .now)

        XCTAssertLessThan(result.adherenceScore, 10)
    }
}
