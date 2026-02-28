import Foundation
import CoreData
import ComeSanoCore

public final class PersistenceController: @unchecked Sendable {
    public let container: NSPersistentCloudKitContainer

    public init(
        containerIdentifier: String,
        inMemory: Bool = false
    ) {
        let model = Self.makeManagedObjectModel()
        container = NSPersistentCloudKitContainer(name: "ComeSanoData", managedObjectModel: model)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        let cloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        description.cloudKitContainerOptions = cloudKitOptions
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

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
            makeAttribute(name: "calories", type: .doubleAttributeType),
            makeAttribute(name: "proteinGrams", type: .doubleAttributeType),
            makeAttribute(name: "carbsGrams", type: .doubleAttributeType),
            makeAttribute(name: "fatGrams", type: .doubleAttributeType),
            makeAttribute(name: "source", type: .stringAttributeType)
        ]

        let pantryEntity = NSEntityDescription()
        pantryEntity.name = "PantryRecord"
        pantryEntity.managedObjectClassName = NSStringFromClass(PantryRecord.self)
        pantryEntity.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType),
            makeAttribute(name: "name", type: .stringAttributeType),
            makeAttribute(name: "quantity", type: .doubleAttributeType),
            makeAttribute(name: "unit", type: .stringAttributeType),
            makeAttribute(name: "expiryDate", type: .dateAttributeType, optional: true)
        ]

        let shoppingEntity = NSEntityDescription()
        shoppingEntity.name = "ShoppingListRecord"
        shoppingEntity.managedObjectClassName = NSStringFromClass(ShoppingListRecord.self)
        shoppingEntity.properties = [
            makeAttribute(name: "id", type: .UUIDAttributeType),
            makeAttribute(name: "name", type: .stringAttributeType),
            makeAttribute(name: "quantity", type: .doubleAttributeType),
            makeAttribute(name: "unit", type: .stringAttributeType),
            makeAttribute(name: "isPurchased", type: .booleanAttributeType)
        ]

        model.entities = [foodEntity, pantryEntity, shoppingEntity]
        return model
    }

    private static func makeAttribute(name: String, type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
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
    @NSManaged var source: String
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
    @NSManaged var quantity: Double
    @NSManaged var unit: String
    @NSManaged var isPurchased: Bool
}
