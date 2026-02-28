import Foundation
import CoreData
import ComeSanoCore

public actor CoreDataStores: FoodCatalogStore, PantryStore, ShoppingListStore {
    private let controller: PersistenceController

    public init(controller: PersistenceController) {
        self.controller = controller
    }

    public func save(foodItems: [FoodItem]) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            try Self.deleteAll(entityName: "FoodRecord", in: context)

            for item in foodItems {
                let record = FoodRecord(context: context)
                record.id = item.id
                record.name = item.name
                record.servingDescription = item.servingDescription
                record.calories = item.nutrition.calories
                record.proteinGrams = item.nutrition.proteinGrams
                record.carbsGrams = item.nutrition.carbsGrams
                record.fatGrams = item.nutrition.fatGrams
                record.source = item.source
            }

            try context.save()
        }
    }

    public func fetchFoodItems() async throws -> [FoodItem] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<FoodRecord>(entityName: "FoodRecord")
            let records = try context.fetch(request)
            return records.map {
                FoodItem(
                    id: $0.id,
                    name: $0.name,
                    servingDescription: $0.servingDescription,
                    nutrition: NutritionPerServing(
                        calories: $0.calories,
                        proteinGrams: $0.proteinGrams,
                        carbsGrams: $0.carbsGrams,
                        fatGrams: $0.fatGrams
                    ),
                    source: $0.source
                )
            }
        }
    }

    public func save(pantryItems: [PantryItem]) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            try Self.deleteAll(entityName: "PantryRecord", in: context)

            for item in pantryItems {
                let record = PantryRecord(context: context)
                record.id = item.id
                record.name = item.name
                record.quantity = item.quantity
                record.unit = item.unit
                record.expiryDate = item.expiryDate
            }

            try context.save()
        }
    }

    public func fetchPantryItems() async throws -> [PantryItem] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<PantryRecord>(entityName: "PantryRecord")
            let records = try context.fetch(request)
            return records.map {
                PantryItem(
                    id: $0.id,
                    name: $0.name,
                    quantity: $0.quantity,
                    unit: $0.unit,
                    expiryDate: $0.expiryDate
                )
            }
        }
    }

    public func save(shoppingItems: [ShoppingListItem]) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            try Self.deleteAll(entityName: "ShoppingListRecord", in: context)

            for item in shoppingItems {
                let record = ShoppingListRecord(context: context)
                record.id = item.id
                record.name = item.name
                record.quantity = item.quantity
                record.unit = item.unit
                record.isPurchased = item.isPurchased
            }

            try context.save()
        }
    }

    public func fetchShoppingItems() async throws -> [ShoppingListItem] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = NSFetchRequest<ShoppingListRecord>(entityName: "ShoppingListRecord")
            let records = try context.fetch(request)
            return records.map {
                ShoppingListItem(
                    id: $0.id,
                    name: $0.name,
                    quantity: $0.quantity,
                    unit: $0.unit,
                    isPurchased: $0.isPurchased
                )
            }
        }
    }

    private nonisolated static func deleteAll(entityName: String, in context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try context.execute(deleteRequest)
    }
}
