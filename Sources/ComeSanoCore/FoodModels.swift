import Foundation

public struct NutritionPerServing: Codable, Sendable {
    public var calories: Double
    public var proteinGrams: Double
    public var carbsGrams: Double
    public var fatGrams: Double
    public var fiberGrams: Double

    public init(calories: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double, fiberGrams: Double = 0) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
    }

    private enum CodingKeys: String, CodingKey {
        case calories, proteinGrams, carbsGrams, fatGrams, fiberGrams
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        proteinGrams = try container.decodeIfPresent(Double.self, forKey: .proteinGrams) ?? 0
        carbsGrams = try container.decodeIfPresent(Double.self, forKey: .carbsGrams) ?? 0
        fatGrams = try container.decodeIfPresent(Double.self, forKey: .fatGrams) ?? 0
        fiberGrams = try container.decodeIfPresent(Double.self, forKey: .fiberGrams) ?? 0
    }
}

public struct FoodItem: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var servingDescription: String
    public var nutrition: NutritionPerServing
    public var source: String
    public var loggedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        servingDescription: String,
        nutrition: NutritionPerServing,
        source: String,
        loggedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.servingDescription = servingDescription
        self.nutrition = nutrition
        self.source = source
        self.loggedAt = loggedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, servingDescription, nutrition, source, loggedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        servingDescription = try container.decode(String.self, forKey: .servingDescription)
        nutrition = try container.decode(NutritionPerServing.self, forKey: .nutrition)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "ai"
        loggedAt = try container.decodeIfPresent(Date.self, forKey: .loggedAt)
    }
}

public struct PantryItem: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var quantity: Double
    public var unit: String
    public var expiryDate: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        quantity: Double,
        unit: String,
        expiryDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
    }
}

public struct ShoppingListItem: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var category: String
    public var quantity: Double
    public var unit: String
    public var isPurchased: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        category: String = "Otros",
        quantity: Double,
        unit: String,
        isPurchased: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.isPurchased = isPurchased
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, quantity, unit, isPurchased
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Otros"
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity) ?? 1
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? "pieza"
        isPurchased = try container.decodeIfPresent(Bool.self, forKey: .isPurchased) ?? false
    }
}
