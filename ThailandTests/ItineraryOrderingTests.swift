import XCTest
import CoreData
@testable import Thailand

final class ItineraryOrderingTests: XCTestCase {

    // MARK: Pure helpers

    func testInsertBeforeTargetReordersWithinList() {
        let result = ItineraryOrdering.inserting("D", before: "B", in: ["A", "B", "C", "D"])
        XCTAssertEqual(result, ["A", "D", "B", "C"])
    }

    func testInsertWithNilTargetAppends() {
        XCTAssertEqual(ItineraryOrdering.inserting("A", before: nil, in: ["A", "B", "C"]), ["B", "C", "A"])
    }

    func testInsertNewIDFromAnotherList() {
        XCTAssertEqual(ItineraryOrdering.inserting("X", before: "B", in: ["A", "B"]), ["A", "X", "B"])
    }

    func testInsertBeforeItselfKeepsItInList() {
        let result = ItineraryOrdering.inserting("B", before: "B", in: ["A", "B", "C"])
        XCTAssertEqual(result.sorted(), ["A", "B", "C"])
        XCTAssertEqual(result.count, 3)
    }

    func testInsertBeforeMissingTargetAppends() {
        XCTAssertEqual(ItineraryOrdering.inserting("A", before: "Z", in: ["A", "B"]), ["B", "A"])
    }

    func testMovingMatchesSwiftUISemantics() {
        // Move first item to the end (SwiftUI passes toOffset = count).
        XCTAssertEqual(ItineraryOrdering.moving(["A", "B", "C"], fromOffsets: [0], toOffset: 3), ["B", "C", "A"])
        // Move last item to the top.
        XCTAssertEqual(ItineraryOrdering.moving(["A", "B", "C"], fromOffsets: [2], toOffset: 0), ["C", "A", "B"])
        // Move two items down together.
        XCTAssertEqual(ItineraryOrdering.moving(["A", "B", "C", "D"], fromOffsets: [0, 1], toOffset: 3), ["C", "A", "B", "D"])
        // No-op move.
        XCTAssertEqual(ItineraryOrdering.moving(["A", "B", "C"], fromOffsets: [1], toOffset: 1), ["A", "B", "C"])
    }

    func testMovingIgnoresOutOfRangeOffsets() {
        XCTAssertEqual(ItineraryOrdering.moving(["A", "B"], fromOffsets: [5], toOffset: 0), ["A", "B"])
    }

    func testDayDatesInclusiveAndOrdered() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 15))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 9))!
        let dates = ItineraryOrdering.dayDates(from: start, to: end, calendar: calendar)
        XCTAssertEqual(dates.count, 4)
        XCTAssertEqual(dates.first, calendar.startOfDay(for: start))
        XCTAssertEqual(dates.last, calendar.startOfDay(for: end))
    }

    func testDayDatesHandlesReversedRangeAndLimit() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(-2 * 86_400)
        XCTAssertEqual(ItineraryOrdering.dayDates(from: start, to: end).count, 3)
        let far = start.addingTimeInterval(400 * 86_400)
        XCTAssertEqual(ItineraryOrdering.dayDates(from: start, to: far, limit: 90).count, 90)
    }

    // MARK: Core Data store

    private var context: NSManagedObjectContext!
    private var store: ItineraryStore!
    private var trip: Trip!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).viewContext
        store = ItineraryStore(context: context)
        let start = Calendar.current.startOfDay(for: .now)
        trip = store.createTrip(name: "Test", start: start, end: start.addingTimeInterval(2 * 86_400))
    }

    override func tearDown() {
        context = nil
        store = nil
        trip = nil
        super.tearDown()
    }

    private func titles(_ items: [Item]) -> [String] { items.map { $0.title ?? "" } }

    func testCreateTripMakesOneDayPerDate() {
        XCTAssertEqual(trip.sortedDays.count, 3)
        XCTAssertEqual(trip.sortedDays.map(\.sortIndex), [0, 1, 2])
    }

    func testAddItemAppendsInOrder() {
        let day = trip.sortedDays[0]
        store.addItem(title: "A", category: .place, to: day, in: trip)
        store.addItem(title: "B", category: .meal, to: day, in: trip)
        store.addItem(title: "C", category: .activity, to: day, in: trip)
        XCTAssertEqual(titles(day.sortedItems), ["A", "B", "C"])
    }

    func testMoveWithinDayBeforeTarget() {
        let day = trip.sortedDays[0]
        let a = store.addItem(title: "A", category: .place, to: day, in: trip)
        store.addItem(title: "B", category: .place, to: day, in: trip)
        let c = store.addItem(title: "C", category: .place, to: day, in: trip)
        store.move(c, toDay: day, in: trip, before: a)
        XCTAssertEqual(titles(day.sortedItems), ["C", "A", "B"])
    }

    func testScheduleFromWishListOntoDay() {
        let day = trip.sortedDays[1]
        let wish = store.addItem(title: "Wish", category: .place, to: nil, in: trip)
        store.addItem(title: "Other wish", category: .place, to: nil, in: trip)
        let existing = store.addItem(title: "Existing", category: .place, to: day, in: trip)

        store.move(wish, toDay: day, in: trip, before: existing)

        XCTAssertEqual(titles(day.sortedItems), ["Wish", "Existing"])
        XCTAssertEqual(titles(trip.sortedWishItems), ["Other wish"])
        XCTAssertEqual(trip.sortedWishItems.first?.sortIndex, 0)
        XCTAssertFalse(wish.isOnWishList)
        XCTAssertNil(wish.wishTrip)
    }

    func testMoveBetweenDaysRenumbersBoth() {
        let first = trip.sortedDays[0]
        let second = trip.sortedDays[1]
        let a = store.addItem(title: "A", category: .place, to: first, in: trip)
        store.addItem(title: "B", category: .place, to: first, in: trip)
        store.addItem(title: "X", category: .place, to: second, in: trip)

        store.move(a, toDay: second, in: trip, before: nil)

        XCTAssertEqual(titles(first.sortedItems), ["B"])
        XCTAssertEqual(first.sortedItems.map(\.sortIndex), [0])
        XCTAssertEqual(titles(second.sortedItems), ["X", "A"])
        XCTAssertEqual(second.sortedItems.map(\.sortIndex), [0, 1])
    }

    func testMoveBackToWishList() {
        let day = trip.sortedDays[0]
        let a = store.addItem(title: "A", category: .place, to: day, in: trip)
        store.move(a, toDay: nil, in: trip, before: nil)
        XCTAssertTrue(a.isOnWishList)
        XCTAssertEqual(a.trip, trip)
        XCTAssertTrue(day.sortedItems.isEmpty)
    }

    func testShorteningTripMovesItemsToWishList() {
        let lastDay = trip.sortedDays[2]
        store.addItem(title: "Late", category: .place, to: lastDay, in: trip)
        let start = trip.startDate!
        store.setDates(of: trip, start: start, end: start.addingTimeInterval(86_400))
        XCTAssertEqual(trip.sortedDays.count, 2)
        XCTAssertEqual(titles(trip.sortedWishItems), ["Late"])
    }

    func testDeleteRenumbersRemaining() {
        let day = trip.sortedDays[0]
        store.addItem(title: "A", category: .place, to: day, in: trip)
        let b = store.addItem(title: "B", category: .place, to: day, in: trip)
        store.addItem(title: "C", category: .place, to: day, in: trip)
        store.delete(b)
        context.processPendingChanges()
        XCTAssertEqual(titles(day.sortedItems), ["A", "C"])
        XCTAssertEqual(day.sortedItems.map(\.sortIndex), [0, 1])
    }

    func testReorderWithOnMoveOffsets() {
        let day = trip.sortedDays[0]
        ["A", "B", "C"].forEach { store.addItem(title: $0, category: .place, to: day, in: trip) }
        store.reorder(day.sortedItems, fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(titles(day.sortedItems), ["B", "C", "A"])
    }

    func testSampleTripLoads() {
        let demo = SampleTrip.create(in: context, startingIn: 10)
        XCTAssertEqual(demo.sortedDays.count, 6)
        XCTAssertFalse(demo.sortedWishItems.isEmpty)
        XCTAssertFalse(demo.sortedPackingItems.isEmpty)
        XCTAssertEqual(demo.sortedExpenses.count, 3)
    }
}
