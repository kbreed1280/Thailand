import CoreData
import CoreLocation
import XCTest
@testable import Thailand

@MainActor
final class CollectionTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var trip: Trip!

    override func setUp() {
        context = PersistenceController(inMemory: true).viewContext
        trip = ItineraryStore(context: context).createTrip(name: "Test", start: .now, end: .now.addingTimeInterval(86_400))
    }

    private func spot(_ name: String, lat: Double, lon: Double, id: String = "") -> Spot {
        let s = Spot(context: context)
        s.uuid = UUID(); s.name = name; s.city = "Bangkok"; s.coordinate = .init(latitude: lat, longitude: lon)
        s.appleMapsID = id; s.status = .confirmed; s.createdAt = .now; s.trip = trip
        return s
    }

    func testAddIsIdempotentAndReorders() {
        let c = CollectionStore.create(name: "Noodles", emoji: "🍜", kind: .theme, in: trip, context: context)
        let a = spot("Jay Fai", lat: 13.7525, lon: 100.5048), b = spot("Thipsamai", lat: 13.7527, lon: 100.5050)
        CollectionStore.add(a, to: c, context: context)
        CollectionStore.add(a, to: c, context: context)
        CollectionStore.add(b, to: c, context: context)
        XCTAssertEqual(c.spots, [a, b])
        CollectionStore.move(in: c, from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(c.spots, [b, a])
        XCTAssertEqual(a.collections, [c])
        CollectionStore.remove(a, from: c, context: context)
        XCTAssertEqual(c.spots, [b])
    }

    func testShareFileRoundTripMergesDuplicates() throws {
        let c = CollectionStore.create(name: "Bangkok eats", emoji: "🌶️", kind: .city, in: trip, context: context)
        let jayFai = spot("Jay Fai", lat: 13.7525, lon: 100.5048, id: "I123")
        CollectionStore.add(jayFai, to: c, note: "Crab omelette, go at 9am", context: context)

        let shared = try SharedCollection.decode(SharedCollection(c, sharedBy: "Kyle").encoded())
        XCTAssertEqual(shared.spots.first?.note, "Crab omelette, go at 9am")
        XCTAssertEqual(shared.sharedBy, "Kyle")

        // Friend's trip: one spot already saved (same Apple Maps ID) → merged, not duplicated.
        let other = ItineraryStore(context: context).createTrip(name: "Friend", start: .now, end: .now.addingTimeInterval(86_400))
        let existing = Spot(context: context)
        existing.uuid = UUID(); existing.name = "Raan Jay Fai"; existing.appleMapsID = "I123"
        existing.coordinate = .init(latitude: 13.7525, longitude: 100.5048); existing.status = .confirmed; existing.trip = other
        let imported = CollectionImporter.saveAll(shared, trip: other, context: context)
        XCTAssertEqual(other.allSpots.count, 1)
        XCTAssertEqual(imported.spots, [existing])
        XCTAssertEqual(imported.sortedEntries.first?.note, "Crab omelette, go at 9am")

        // Importing again doesn't add the spot twice.
        CollectionImporter.saveAll(shared, trip: other, context: context)
        XCTAssertEqual(other.sortedCollections.count, 1)
        XCTAssertEqual(imported.spots.count, 1)
    }
}
