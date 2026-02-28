import Foundation

public protocol DailyCalorieBurnProvider: Sendable {
    func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double)
}

public protocol DailyIntakeProvider: Sendable {
    func fetchConsumedCalories(for date: Date) async throws -> Double
}

public protocol DietaryEnergyWriter: Sendable {
    func saveDietaryEnergy(kilocalories: Double, at date: Date) async throws
}

public struct NutritionInferenceResult: Codable, Sendable {
    public var foodItems: [FoodItem]
    public var notes: String

    public init(foodItems: [FoodItem], notes: String) {
        self.foodItems = foodItems
        self.notes = notes
    }
}

public protocol MultimodalNutritionInference: Sendable {
    func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult
}
