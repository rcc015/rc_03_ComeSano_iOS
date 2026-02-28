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
    public var shoppingList: [ShoppingListItem]
    public var notes: String

    public init(foodItems: [FoodItem], shoppingList: [ShoppingListItem] = [], notes: String) {
        self.foodItems = foodItems
        self.shoppingList = shoppingList
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case foodItems, shoppingList, notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        foodItems = try container.decodeIfPresent([FoodItem].self, forKey: .foodItems) ?? []
        shoppingList = try container.decodeIfPresent([ShoppingListItem].self, forKey: .shoppingList) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

public protocol MultimodalNutritionInference: Sendable {
    func inferNutrition(fromImageData data: Data, prompt: String) async throws -> NutritionInferenceResult
}
