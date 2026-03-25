import Foundation
import CoreData
import ComeSanoCore

public final class PersistenceController: @unchecked Sendable {
    public let container: NSPersistentContainer

    public init(inMemory: Bool = false) {
        let model = Self.makeManagedObjectModel()
        container = NSPersistentContainer(name: "ComeSanoData", managedObjectModel: model)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load persistent stores: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let foodEntity = NSEntityDescription()
        foodEntity.name = "FoodRecord"
        foodEntity.managedObjectClassName = NSStringFromClass(FoodRecord.self)
        foodEntity.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType),
            makeAttribute(name: "name", type: .stringAttributeType),
            makeAttribute(name: "servingDescription", type: .stringAttributeType),
            makeAttribute(name: "calories", type: .doubleAttributeType, defaultValue: 0),
            makeAttribute(name: "proteinGrams", type: .doubleAttributeType, defaultValue: 0),
            makeAttribute(name: "carbsGrams", type: .doubleAttributeType, defaultValue: 0),
            makeAttribute(name: "fatGrams", type: .doubleAttributeType, defaultValue: 0),
            makeAttribute(name: "fiberGrams", type: .doubleAttributeType, defaultValue: 0),
            makeAttribute(name: "source", type: .stringAttributeType),
            makeAttribute(name: "loggedAt", type: .dateAttributeType, optional: true)
        ]

        let pantryEntity = NSEntityDescription()
        pantryEntity.name = "PantryRecord"
        pantryEntity.managedObjectClassName = NSStringFromClass(PantryRecord.self)
        pantryEntity.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType),
            makeAttribute(name: "name", type: .stringAttributeType),
            makeAttribute(name: "quantity", type: .doubleAttributeType, defaultValue: 0),
            makeAttribute(name: "unit", type: .stringAttributeType),
            makeAttribute(name: "expiryDate", type: .dateAttributeType, optional: true)
        ]

        let shoppingEntity = NSEntityDescription()
        shoppingEntity.name = "ShoppingListRecord"
        shoppingEntity.managedObjectClassName = NSStringFromClass(ShoppingListRecord.self)
        shoppingEntity.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType),
            makeAttribute(name: "name", type: .stringAttributeType),
            makeAttribute(name: "category", type: .stringAttributeType, optional: true),
            makeAttribute(name: "quantity", type: .doubleAttributeType, defaultValue: 0),
            makeAttribute(name: "unit", type: .stringAttributeType),
            makeAttribute(name: "isPurchased", type: .booleanAttributeType, defaultValue: false)
        ]

        model.entities = [foodEntity, pantryEntity, shoppingEntity]
        return model
    }

    private static func makeAttribute(
        name: String,
        type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }
}

@objc(FoodRecord)
final class FoodRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var servingDescription: String
    @NSManaged var calories: Double
    @NSManaged var proteinGrams: Double
    @NSManaged var carbsGrams: Double
    @NSManaged var fatGrams: Double
    @NSManaged var fiberGrams: Double
    @NSManaged var source: String
    @NSManaged var loggedAt: Date?
}

@objc(PantryRecord)
final class PantryRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var quantity: Double
    @NSManaged var unit: String
    @NSManaged var expiryDate: Date?
}

@objc(ShoppingListRecord)
final class ShoppingListRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var category: String?
    @NSManaged var quantity: Double
    @NSManaged var unit: String
    @NSManaged var isPurchased: Bool
}
