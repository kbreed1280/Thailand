import CoreData

/// The Core Data model, defined in code.
///
/// It follows CloudKit's rules so trips can sync and be shared with `NSPersistentCloudKitContainer`:
/// every attribute is optional or has a default, every relationship is optional with an inverse,
/// no relationship is ordered (we store `sortIndex` instead) and there are no unique constraints.
enum TripModel {
    /// One shared instance: loading the same entities from two model objects confuses Core Data.
    static let model: NSManagedObjectModel = makeModel()

    private static func makeModel() -> NSManagedObjectModel {
        let trip = entity("Trip", [
            attribute("uuid", .UUIDAttributeType),
            attribute("name", .stringAttributeType, default: ""),
            attribute("startDate", .dateAttributeType),
            attribute("endDate", .dateAttributeType),
            attribute("notes", .stringAttributeType, default: ""),
            attribute("hotelAddressThai", .stringAttributeType, default: ""),
            attribute("createdAt", .dateAttributeType),
            attribute("colorHex", .stringAttributeType, default: ""),
            attribute("coverPhotoID", .UUIDAttributeType)
        ])

        let day = entity("Day", [
            attribute("uuid", .UUIDAttributeType),
            attribute("date", .dateAttributeType),
            attribute("title", .stringAttributeType, default: ""),
            attribute("sortIndex", .integer64AttributeType, default: 0)
        ])

        let item = entity("Item", [
            attribute("uuid", .UUIDAttributeType),
            attribute("title", .stringAttributeType, default: ""),
            attribute("categoryRaw", .stringAttributeType, default: ItemCategory.place.rawValue),
            attribute("time", .dateAttributeType),
            attribute("notes", .stringAttributeType, default: ""),
            attribute("address", .stringAttributeType, default: ""),
            attribute("hasCoordinate", .booleanAttributeType, default: false),
            attribute("latitude", .doubleAttributeType, default: 0),
            attribute("longitude", .doubleAttributeType, default: 0),
            attribute("link", .stringAttributeType, default: ""),
            attribute("costTHB", .doubleAttributeType, default: 0),
            attribute("statusRaw", .stringAttributeType, default: ItemStatus.wantToGo.rawValue),
            attribute("sortIndex", .integer64AttributeType, default: 0),
            attribute("addedBy", .stringAttributeType, default: ""),
            attribute("lastEditedBy", .stringAttributeType, default: ""),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("durationMinutes", .integer64AttributeType, default: 60),
            attribute("travelModeRaw", .stringAttributeType, default: TravelMode.walking.rawValue)
        ])

        let photo = entity("ItemPhoto", [
            attribute("uuid", .UUIDAttributeType),
            attribute("imageData", .binaryDataAttributeType, externalStorage: true),
            attribute("thumbnailData", .binaryDataAttributeType, externalStorage: true),
            attribute("createdAt", .dateAttributeType)
        ])

        let visit = entity("VisitLog", [
            attribute("uuid", .UUIDAttributeType),
            attribute("date", .dateAttributeType),
            attribute("placeName", .stringAttributeType, default: ""),
            attribute("latitude", .doubleAttributeType, default: 0),
            attribute("longitude", .doubleAttributeType, default: 0)
        ])

        let expense = entity("Expense", [
            attribute("uuid", .UUIDAttributeType),
            attribute("title", .stringAttributeType, default: ""),
            attribute("amountTHB", .doubleAttributeType, default: 0),
            attribute("paidBy", .stringAttributeType, default: ""),
            attribute("splitRaw", .stringAttributeType, default: ExpenseSplit.equal.rawValue),
            attribute("payerShare", .doubleAttributeType, default: 0.5),
            attribute("categoryRaw", .stringAttributeType, default: ExpenseCategory.food.rawValue),
            attribute("date", .dateAttributeType),
            attribute("addedBy", .stringAttributeType, default: "")
        ])

        let packing = entity("PackingItem", [
            attribute("uuid", .UUIDAttributeType),
            attribute("title", .stringAttributeType, default: ""),
            attribute("categoryRaw", .stringAttributeType, default: PackingCategory.essentials.rawValue),
            attribute("isDone", .booleanAttributeType, default: false),
            attribute("sortIndex", .integer64AttributeType, default: 0),
            attribute("addedBy", .stringAttributeType, default: "")
        ])

        let savedPlace = entity("SavedPlace", [
            attribute("uuid", .UUIDAttributeType),
            attribute("name", .stringAttributeType, default: ""),
            attribute("address", .stringAttributeType, default: ""),
            attribute("latitude", .doubleAttributeType, default: 0),
            attribute("longitude", .doubleAttributeType, default: 0),
            attribute("symbolName", .stringAttributeType, default: "bed.double.fill"),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ])

        let document = entity("TripDocument", [
            attribute("uuid", .UUIDAttributeType),
            attribute("title", .stringAttributeType, default: ""),
            attribute("kindRaw", .stringAttributeType, default: DocumentKind.note.rawValue),
            attribute("fileData", .binaryDataAttributeType, externalStorage: true),
            attribute("fileExtension", .stringAttributeType, default: ""),
            attribute("urlString", .stringAttributeType, default: ""),
            attribute("text", .stringAttributeType, default: ""),
            attribute("addedBy", .stringAttributeType, default: ""),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ])

        relate(trip, "days", toMany: day, inverse: "trip", deleteRule: .cascadeDeleteRule)
        relate(trip, "documents", toMany: document, inverse: "trip", deleteRule: .cascadeDeleteRule)
        relate(trip, "savedPlaces", toMany: savedPlace, inverse: "trip", deleteRule: .cascadeDeleteRule)
        relate(trip, "wishItems", toMany: item, inverse: "wishTrip", deleteRule: .cascadeDeleteRule)
        relate(trip, "visits", toMany: visit, inverse: "trip", deleteRule: .cascadeDeleteRule)
        relate(trip, "expenses", toMany: expense, inverse: "trip", deleteRule: .cascadeDeleteRule)
        relate(trip, "packingItems", toMany: packing, inverse: "trip", deleteRule: .cascadeDeleteRule)
        relate(day, "items", toMany: item, inverse: "day", deleteRule: .cascadeDeleteRule)
        relate(item, "photos", toMany: photo, inverse: "item", deleteRule: .cascadeDeleteRule)

        let model = NSManagedObjectModel()
        model.entities = [trip, day, item, photo, visit, expense, packing, savedPlace, document]
        return model
    }

    // MARK: Builders

    private static func entity(_ name: String, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = name // classes are exposed to Obj-C under their plain names
        entity.properties = attributes
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        default defaultValue: Any? = nil,
        externalStorage: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = defaultValue
        attribute.allowsExternalBinaryDataStorage = externalStorage
        return attribute
    }

    /// Adds a to-many relationship on `owner` and its to-one inverse on `child`.
    private static func relate(
        _ owner: NSEntityDescription,
        _ name: String,
        toMany child: NSEntityDescription,
        inverse inverseName: String,
        deleteRule: NSDeleteRule
    ) {
        let toMany = NSRelationshipDescription()
        toMany.name = name
        toMany.destinationEntity = child
        toMany.minCount = 0
        toMany.maxCount = 0
        toMany.isOptional = true
        toMany.deleteRule = deleteRule

        let toOne = NSRelationshipDescription()
        toOne.name = inverseName
        toOne.destinationEntity = owner
        toOne.minCount = 0
        toOne.maxCount = 1
        toOne.isOptional = true
        toOne.deleteRule = .nullifyDeleteRule

        toMany.inverseRelationship = toOne
        toOne.inverseRelationship = toMany

        owner.properties.append(toMany)
        child.properties.append(toOne)
    }
}
