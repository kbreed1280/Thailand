import CoreData
import XCTest
@testable import Thailand

final class StoreMigrationTests: XCTestCase {
    func testCopiesEveryObjectAndRelationship() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "old.sqlite"), destination = dir.appending(path: "new.sqlite")

        // A store with the demo trip (days, items, spots, packing…).
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: TripModel.model)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: source,
                                           options: [NSPersistentHistoryTrackingKey: true as NSNumber])
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let trip = SampleTrip.create(in: context)
        try context.save()
        let days = trip.sortedDays.count, items = trip.allItems.count, name = trip.displayName
        XCTAssertGreaterThan(items, 0)
        for store in coordinator.persistentStores { try coordinator.remove(store) }

        try StoreMigration.copyAll(from: source, to: destination, model: TripModel.model)

        let check = NSPersistentStoreCoordinator(managedObjectModel: TripModel.model)
        try check.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: destination,
                                     options: [NSPersistentHistoryTrackingKey: true as NSNumber])
        let checkContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        checkContext.persistentStoreCoordinator = check
        let copied = try checkContext.fetch(NSFetchRequest<Trip>(entityName: "Trip"))
        XCTAssertEqual(copied.count, 1)
        XCTAssertEqual(copied.first?.displayName, name)
        XCTAssertEqual(copied.first?.sortedDays.count, days)
        XCTAssertEqual(copied.first?.allItems.count, items)
    }
}
