import Foundation

public enum CalorieMath {
    public static func weeklyProgress(from snapshots: [DailyCalorieSnapshot], weekStart: Date) -> WeeklyProgress {
        guard !snapshots.isEmpty else {
            return WeeklyProgress(weekStart: weekStart, averageNetKcal: 0, averageTargetDeltaKcal: 0, adherenceScore: 0)
        }

        let net = snapshots.reduce(0) { $0 + $1.netKcal } / Double(snapshots.count)
        let delta = snapshots.reduce(0) { $0 + $1.targetDeltaKcal } / Double(snapshots.count)

        // 100 means the user is on target; every 100 kcal away from target reduces score by 10 points.
        let score = max(0, 100 - abs(delta) / 10)

        return WeeklyProgress(
            weekStart: weekStart,
            averageNetKcal: net,
            averageTargetDeltaKcal: delta,
            adherenceScore: score
        )
    }
}
