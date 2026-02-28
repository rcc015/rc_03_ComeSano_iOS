import Foundation
import ComeSanoCore

#if canImport(HealthKit)
import HealthKit

public final class HealthKitCalorieBurnProvider: DailyCalorieBurnProvider {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func requestAuthorization() async throws {
        let types: Set = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned)
        ]

        try await healthStore.requestAuthorization(toShare: [], read: types)
    }

    public func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double) {
        async let active = sumQuantity(for: .activeEnergyBurned, on: date)
        async let basal = sumQuantity(for: .basalEnergyBurned, on: date)
        return try await (active, basal)
    }

    private func sumQuantity(for identifier: HKQuantityTypeIdentifier, on date: Date) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let quantityType = HKQuantityType(identifier)
            let start = Calendar.current.startOfDay(for: date)
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
                continuation.resume(returning: 0)
                return
            }

            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let kcal = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }

            healthStore.execute(query)
        }
    }
}

#else

public final class HealthKitCalorieBurnProvider: DailyCalorieBurnProvider {
    public init() {}

    public func requestAuthorization() async throws {}

    public func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double) {
        _ = date
        return (active: 0, basal: 0)
    }
}

#endif
