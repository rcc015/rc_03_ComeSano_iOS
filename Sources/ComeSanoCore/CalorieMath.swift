import Foundation

public enum CalorieMath {
    public static func weeklyProgress(from snapshots: [DailyCalorieSnapshot], weekStart: Date) -> WeeklyProgress {
        guard !snapshots.isEmpty else {
            return WeeklyProgress(weekStart: weekStart, averageNetKcal: 0, averageTargetDeltaKcal: 0, adherenceScore: 0)
        }

        let net = snapshots.reduce(0) { $0 + $1.netKcal } / Double(snapshots.count)
        let delta = snapshots.reduce(0) { $0 + $1.targetDeltaKcal } / Double(snapshots.count)

        // 100 means a balanced day (intake ~= real burn). Every 100 kcal net deviation reduces score by 10.
        let score = max(0, 100 - abs(net) / 10)

        return WeeklyProgress(
            weekStart: weekStart,
            averageNetKcal: net,
            averageTargetDeltaKcal: delta,
            adherenceScore: score
        )
    }
}
