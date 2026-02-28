import Foundation

public protocol FoodCatalogStore: Sendable {
    func save(foodItems: [FoodItem]) async throws
    func fetchFoodItems() async throws -> [FoodItem]
}

public protocol PantryStore: Sendable {
    func save(pantryItems: [PantryItem]) async throws
    func fetchPantryItems() async throws -> [PantryItem]
}

public protocol ShoppingListStore: Sendable {
    func save(shoppingItems: [ShoppingListItem]) async throws
    func fetchShoppingItems() async throws -> [ShoppingListItem]
}
