import CoreData
import XCTest
@testable import Thailand

/// The app has shipped with the pre-step-13 model. Adding Spot / SpotSource / SpotScoop must
/// migrate existing stores in place (lightweight, inferred) without losing trips.
final class MigrationTests: XCTestCase {
    func testExistingTripsSurviveAddingSpots() throws { try migrate(from: .step12) }

    /// Your phone has the step-13 store (spots) already.
    func testStep13StoreMigratesToCollections() throws { try migrate(from: .step13) }

    private func migrate(from version: TripModel.Version) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // 1. A store written by the old model, like the one on your phone today.
        let oldModel = TripModel.makeModel(version: version)
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        let oldStore = try oldCoordinator.addPersistentStore(type: .sqlite, at: url)
        let oldContext = NSManagedObjectContext(.mainQueue)
        oldContext.persistentStoreCoordinator = oldCoordinator
        let trip = NSManagedObject(entity: oldModel.entitiesByName["Trip"]!, insertInto: oldContext)
        trip.setValue("Thailand", forKey: "name")
        for title in ["Passport", "Adapter"] {
            let item = NSManagedObject(entity: oldModel.entitiesByName["PackingItem"]!, insertInto: oldContext)
            item.setValue(title, forKey: "title")
            item.setValue(trip, forKey: "trip")
        }
        try oldContext.save()
        try oldCoordinator.remove(oldStore)

        // 2. Reopen with the new model the way the app does (automatic lightweight migration).
        let newModel = TripModel.makeModel()
        let container = NSPersistentContainer(name: "MigrationTest", managedObjectModel: newModel)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Store failed to migrate: \(String(describing: loadError))")

        // 3. Old data is intact and the new entities work.
        let trips = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Trip"))
        XCTAssertEqual(trips.first?.value(forKey: "name") as? String, "Thailand")
        XCTAssertEqual((trips.first?.value(forKey: "packingItems") as? Set<NSManagedObject>)?.count, 2)

        let spot = NSManagedObject(entity: newModel.entitiesByName["Spot"]!, insertInto: container.viewContext)
        spot.setValue("Jay Fai", forKey: "name")
        spot.setValue(trips.first, forKey: "trip")
        let collection = NSManagedObject(entity: newModel.entitiesByName["SpotCollection"]!, insertInto: container.viewContext)
        collection.setValue("Bangkok eats", forKey: "name")
        collection.setValue(trips.first, forKey: "trip")
        trips.first?.setValue("chill", forKey: "vibe")
        XCTAssertNoThrow(try container.viewContext.save())
    }
}
