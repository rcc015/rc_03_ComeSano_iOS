import Foundation

public protocol DailyCalorieBurnProvider: Sendable {
    func fetchBurnedCalories(for date: Date) async throws -> (active: Double, basal: Double)
}

public protocol DailyIntakeProvider: Sendable {
    func fetchConsumedCalories(for date: Date) async throws -> Double
}

public protocol DailyMacroIntakeProvider: Sendable {
    func fetchConsumedMacros(for date: Date) async throws -> (proteinGrams: Double, carbsGrams: Double, fatGrams: Double, fiberGrams: Double)
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

public struct RecipeSuggestion: Codable, Sendable, Identifiable {
    public var id: UUID
    public var nombre: String
    public var tiempoMinutos: Int
    public var calorias: Int
    public var ingredientesUsados: [String]
    public var ingredientesFaltantes: [String]
    public var pasos: [String]

    public init(
        id: UUID = UUID(),
        nombre: String,
        tiempoMinutos: Int,
        calorias: Int,
        ingredientesUsados: [String],
        ingredientesFaltantes: [String],
        pasos: [String] = []
    ) {
        self.id = id
        self.nombre = nombre
        self.tiempoMinutos = tiempoMinutos
        self.calorias = calorias
        self.ingredientesUsados = ingredientesUsados
        self.ingredientesFaltantes = ingredientesFaltantes
        self.pasos = pasos
    }

    private enum CodingKeys: String, CodingKey {
        case id, nombre, tiempoMinutos, calorias, ingredientesUsados, ingredientesFaltantes, pasos
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nombre = try container.decodeIfPresent(String.self, forKey: .nombre) ?? "Receta sugerida"
        tiempoMinutos = try container.decodeIfPresent(Int.self, forKey: .tiempoMinutos) ?? 0
        calorias = try container.decodeIfPresent(Int.self, forKey: .calorias) ?? 0
        ingredientesUsados = try container.decodeIfPresent([String].self, forKey: .ingredientesUsados) ?? []
        ingredientesFaltantes = try container.decodeIfPresent([String].self, forKey: .ingredientesFaltantes) ?? []
        pasos = try container.decodeIfPresent([String].self, forKey: .pasos) ?? []
    }
}

public protocol MultimodalRecipeInference: Sendable {
    func inferRecipes(fromImageData images: [Data], prompt: String) async throws -> [RecipeSuggestion]
}
