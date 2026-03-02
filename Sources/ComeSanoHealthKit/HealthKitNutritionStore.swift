import Foundation
import ComeSanoCore

#if canImport(HealthKit)
import HealthKit

public struct HealthBodyMetrics: Sendable {
    public let weightKG: Double?
    public let heightCM: Double?
    public let ageYears: Int?

    public init(weightKG: Double?, heightCM: Double?, ageYears: Int?) {
        self.weightKG = weightKG
        self.heightCM = heightCM
        self.ageYears = ageYears
    }
}

public final class HealthKitNutritionStore: DailyCalorieBurnProvider, DailyIntakeProvider, DietaryEnergyWriter {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        ]

        let writeTypes: Set<HKSampleType> = [
            HKQuantityType(.dietaryEnergyConsumed)
        ]

        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    public func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double) {
        async let active = sumQuantity(for: .activeEnergyBurned, on: date)
        async let basal = sumQuantity(for: .basalEnergyBurned, on: date)
        return try await (active, basal)
    }

    public func fetchConsumedCalories(for date: Date) async throws -> Double {
        try await sumQuantity(for: .dietaryEnergyConsumed, on: date)
    }

    public func saveDietaryEnergy(kilocalories: Double, at date: Date) async throws {
        let type = HKQuantityType(.dietaryEnergyConsumed)
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "ComeSanoHealthKit", code: -1))
                }
            }
        }
    }

    public func fetchBodyMetrics() async -> HealthBodyMetrics {
        async let weight = latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo))
        async let height = latestQuantity(for: .height, unit: .meterUnit(with: .centi))
        let age = fetchAgeYears()

        let weightValue = await weight
        let heightValue = await height
        return HealthBodyMetrics(weightKG: weightValue, heightCM: heightValue, ageYears: age)
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
                    if Self.shouldTreatAsNoData(error) {
                        continuation.resume(returning: 0)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }

                let kcal = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }

            healthStore.execute(query)
        }
    }

    private static func shouldTreatAsNoData(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == HKErrorDomain, nsError.code == HKError.Code.errorNoData.rawValue {
            return true
        }
        let lower = nsError.localizedDescription.lowercased()
        return lower.contains("no data available")
    }

    private func latestQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let quantityType = HKQuantityType(identifier)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func fetchAgeYears() -> Int? {
        guard let components = try? healthStore.dateOfBirthComponents() else { return nil }
        guard let birthDate = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: .now).year
    }
}

#else

public final class HealthKitNutritionStore: DailyCalorieBurnProvider, DailyIntakeProvider, DietaryEnergyWriter {
    public init() {}

    public func requestAuthorization() async throws {}

    public func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double) {
        _ = date
        return (active: 0, basal: 0)
    }

    public func fetchConsumedCalories(for date: Date) async throws -> Double {
        _ = date
        return 0
    }

    public func saveDietaryEnergy(kilocalories: Double, at date: Date) async throws {
        _ = kilocalories
        _ = date
    }

    public func fetchBodyMetrics() async -> HealthBodyMetrics {
        HealthBodyMetrics(weightKG: nil, heightCM: nil, ageYears: nil)
    }
}

#endif
