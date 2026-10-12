import CoreData
import Foundation

/// One-time move of your data into fresh store files.
///
/// Development installs used to sync with the CloudKit *Development* environment. The old store
/// files remember that environment's zone and shares, so after switching to Production nothing
/// re-uploaded and "Invite" kept reusing a share that only exists in Development. Copying every
/// object into a brand-new store (with no CloudKit bookkeeping) makes iCloud upload everything to
/// Production and create new shares. The old files are kept as a backup.
enum StoreMigration {
    static let doneKey = "storeMigration.productionV2"
    static let privateName = "private-v2.sqlite"
    static let sharedName = "shared-v2.sqlite"

    /// The private store file to use, migrating the old one first if needed.
    static func privateStoreURL(in base: URL, model: NSManagedObjectModel) -> URL {
        let old = base.appending(path: "private.sqlite")
        let new = base.appending(path: privateName)
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: doneKey) { return new }
        // New installs: nothing to move.
        guard FileManager.default.fileExists(atPath: old.path) else {
            defaults.set(true, forKey: doneKey)
            return new
        }
        do {
            try copyAll(from: old, to: new, model: model)
            defaults.set(true, forKey: doneKey)
            NSLog("STORE migrated to %@", new.lastPathComponent)
            return new
        } catch {
            // Keep using the old store rather than risk losing anything.
            NSLog("STORE migration failed: %@", String(describing: error))
            try? FileManager.default.removeItem(at: new)
            return old
        }
    }

    static func sharedStoreURL(in base: URL) -> URL {
        UserDefaults.standard.bool(forKey: doneKey) ? base.appending(path: sharedName) : base.appending(path: "shared.sqlite")
    }

    /// Copies every object (attributes and relationships) from one store file into a new one.
    static func copyAll(from source: URL, to destination: URL, model: NSManagedObjectModel) throws {
        try? FileManager.default.removeItem(at: destination)

        let sourceContext = try context(for: source, model: model, readOnly: true)
        let destinationContext = try context(for: destination, model: model, readOnly: false)

        var failure: Error?
        destinationContext.performAndWait {
            sourceContext.performAndWait {
                do {
                    let count = try copyObjects(from: sourceContext, to: destinationContext, model: model)
                    try destinationContext.save()
                    NSLog("STORE copied %d objects", count)
                } catch {
                    failure = error
                }
            }
        }
        if let failure { throw failure }
    }

    private static func copyObjects(from sourceContext: NSManagedObjectContext, to destinationContext: NSManagedObjectContext,
                                    model: NSManagedObjectModel) throws -> Int {
        let entities = model.entities.filter { !$0.isAbstract && $0.name != nil }
        var copies: [NSManagedObjectID: NSManagedObject] = [:]
        var originals: [NSManagedObject] = []

        // Pass 1: objects and attributes.
        for entity in entities {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity.name!)
            request.includesSubentities = false
            for object in try sourceContext.fetch(request) {
                let copy = NSManagedObject(entity: entity, insertInto: destinationContext)
                for (name, _) in entity.attributesByName {
                    copy.setValue(object.value(forKey: name), forKey: name)
                }
                copies[object.objectID] = copy
                originals.append(object)
            }
        }

        // Pass 2: relationships.
        for object in originals {
            guard let copy = copies[object.objectID] else { continue }
            for (name, relationship) in object.entity.relationshipsByName {
                if relationship.isToMany {
                    if relationship.isOrdered {
                        let related = (object.value(forKey: name) as? NSOrderedSet)?.array as? [NSManagedObject] ?? []
                        copy.setValue(NSOrderedSet(array: related.compactMap { copies[$0.objectID] }), forKey: name)
                    } else {
                        let related = (object.value(forKey: name) as? Set<NSManagedObject>).map(Array.init) ?? []
                        copy.setValue(Set(related.compactMap { copies[$0.objectID] }), forKey: name)
                    }
                } else if let target = object.value(forKey: name) as? NSManagedObject {
                    copy.setValue(copies[target.objectID], forKey: name)
                }
            }
        }
        return copies.count
    }

    private static func context(for url: URL, model: NSManagedObjectModel, readOnly: Bool) throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        var options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            // Same history settings CloudKit sync needs, so the new store is ready to mirror.
            NSPersistentHistoryTrackingKey: true as NSNumber,
            NSPersistentStoreRemoteChangeNotificationPostOptionKey: true as NSNumber,
        ]
        if readOnly { options[NSReadOnlyPersistentStoreOption] = true as NSNumber }
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: options)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}
