import Foundation
import CoreData
import ComeSanoCore

public actor CoreDataStores: FoodCatalogStore, PantryStore, ShoppingListStore, DailyIntakeProvider {
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
                record.loggedAt = item.loggedAt ?? .now
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
                    source: $0.source,
                    loggedAt: $0.loggedAt
                )
            }
        }
    }

    public func fetchConsumedCalories(for date: Date) async throws -> Double {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }

            let request = NSFetchRequest<NSDictionary>(entityName: "FoodRecord")
            request.resultType = .dictionaryResultType
            request.predicate = NSPredicate(format: "loggedAt >= %@ AND loggedAt < %@", start as NSDate, end as NSDate)

            let sumExpression = NSExpressionDescription()
            sumExpression.name = "sumCalories"
            sumExpression.expression = NSExpression(
                forFunction: "sum:",
                arguments: [NSExpression(forKeyPath: "calories")]
            )
            sumExpression.expressionResultType = .doubleAttributeType
            request.propertiesToFetch = [sumExpression]

            let result = try context.fetch(request)
            let total = result.first?["sumCalories"] as? NSNumber
            return total?.doubleValue ?? 0
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
                record.category = item.category
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
                    category: $0.category ?? "Otros",
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
