import CoreData

/// Owns the Core Data stack.
///
/// It uses `NSPersistentCloudKitContainer` from day one so turning on iCloud sync and sharing
/// (step 6) only needs store options, not a data migration. Until then everything stays on device.
final class PersistenceController {
    static let shared = PersistenceController()

    /// In-memory store with the demo trip, for SwiftUI previews.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        SampleTrip.create(in: controller.viewContext)
        return controller
    }()

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Thailand", managedObjectModel: TripModel.model)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        // History tracking + remote change notifications are what CloudKit sync relies on.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        // TODO(step 6): set cloudKitContainerOptions and add the shared store.
        description.cloudKitContainerOptions = nil

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Couldn't load the trip database: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"
    }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            print("Save failed: \(error)")
        }
    }
}
