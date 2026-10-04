import CoreData
import XCTest
@testable import Thailand

/// The app has shipped with the pre-step-13 model. Adding Spot / SpotSource / SpotScoop must
/// migrate existing stores in place (lightweight, inferred) without losing trips.
final class MigrationTests: XCTestCase {
    func testExistingTripsSurviveAddingSpots() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // 1. A store written by the old model, like the one on your phone today.
        let oldModel = TripModel.makeModel(includeSpots: false)
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
        XCTAssertNoThrow(try container.viewContext.save())
    }
}
