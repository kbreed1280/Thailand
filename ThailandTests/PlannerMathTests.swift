import CoreLocation
import XCTest
@testable import Thailand

final class PlannerMathTests: XCTestCase {
    private func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    // MARK: Route optimizer

    func testOptimizerUntanglesAZigZagDay() {
        // Points along a line, visited out of order: 0, 3, 1, 4, 2 (by position).
        let points = [c(13.70, 100.50), c(13.73, 100.50), c(13.71, 100.50), c(13.74, 100.50), c(13.72, 100.50)]
        let order = RouteOptimizer.order(points: points)
        let lats = order.map { points[$0].latitude }
        XCTAssertTrue(lats == lats.sorted() || lats == lats.sorted(by: >), "expected a straight sweep, got \(lats)")
        XCTAssertLessThan(RouteOptimizer.length(order, points: points, start: nil, end: nil),
                          RouteOptimizer.length(Array(points.indices), points: points, start: nil, end: nil))
    }

    func testOptimizerStartsNearTheHotel() {
        let hotel = c(13.70, 100.50)
        let points = [c(13.75, 100.50), c(13.71, 100.50), c(13.73, 100.50)]
        let order = RouteOptimizer.order(points: points, start: hotel, end: hotel)
        XCTAssertEqual(points[order.first!].latitude, 13.71, accuracy: 0.0001)
    }

    func testOptimizerLeavesTinyDaysAlone() {
        XCTAssertEqual(RouteOptimizer.order(points: [c(1, 1), c(2, 2)]), [0, 1])
        XCTAssertEqual(RouteOptimizer.order(points: [c(1, 1)]), [0])
    }

    func testMergedKeepsStopsWithoutLocationInPlace() {
        // "B" has no location and stays second; the mappable stops take the optimized order.
        let merged = RouteOptimizer.merged(all: ["A", "B", "C", "D"], hasLocation: { $0 != "B" }, optimized: ["D", "A", "C"])
        XCTAssertEqual(merged, ["D", "B", "A", "C"])
    }

    func testDistanceIsRoughlyRight() {
        // Bangkok → Chiang Mai is about 585 km in a straight line.
        let d = RouteOptimizer.distance(c(13.7563, 100.5018), c(18.7883, 98.9853))
        XCTAssertEqual(d / 1000, 585, accuracy: 15)
    }

    // MARK: Budget

    func testBudgetParseAndFormatRoundTrip() {
        let budgets: [ExpenseCategory: Double] = [.food: 3000, .lodging: 12000]
        XCTAssertEqual(BudgetMath.parse(BudgetMath.format(budgets)), budgets)
        XCTAssertEqual(BudgetMath.parse("food=abc\nnope=5\nshopping=0"), [:])
    }

    func testBudgetSummary() {
        let summary = BudgetMath.summary(
            total: 20000,
            perCategory: [.food: 5000],
            expenses: [(.food, 1200), (.food, 800), (.transport, 500)],
            plannedCosts: [1500]
        )
        XCTAssertEqual(summary.spent, 2500)
        XCTAssertEqual(summary.remaining, 17500)
        XCTAssertEqual(summary.projected, 4000)
        XCTAssertEqual(summary.lines.first { $0.category == .food }?.remaining, 3000)
        XCTAssertEqual(summary.lines.first { $0.category == .transport }?.budget, 0)
    }

    func testCategoryBudgetsAddUpWhenNoTotal() {
        let summary = BudgetMath.summary(total: 0, perCategory: [.food: 1000, .lodging: 4000], expenses: [], plannedCosts: [])
        XCTAssertEqual(summary.budget, 5000)
    }

    // MARK: Lists & export

    func testListsDedupeAndRename() {
        var stored = TripLists.adding("Restaurants", to: "")
        stored = TripLists.adding("restaurants", to: stored)
        stored = TripLists.adding("Things to do", to: stored)
        XCTAssertEqual(TripLists.names(stored: stored, itemLists: ["Cafés", "Restaurants"]), ["Restaurants", "Things to do", "Cafés"])
        stored = TripLists.renaming("Restaurants", to: "Food", in: stored)
        XCTAssertEqual(TripLists.names(stored: stored, itemLists: []), ["Food", "Things to do"])
        XCTAssertEqual(TripLists.names(stored: TripLists.removing("Food", from: stored), itemLists: []), ["Things to do"])
    }

    func testKMLHasFoldersAndEscapes() {
        let kml = MapExport.kml(title: "Bangkok & Beyond", folders: [
            (name: "Day 1", places: [.init(name: "Wat <Pho>", notes: "", latitude: 13.7465, longitude: 100.4927)]),
            (name: "Empty", places: [])
        ])
        XCTAssertTrue(kml.contains("<name>Bangkok &amp; Beyond</name>"))
        XCTAssertTrue(kml.contains("<name>1. Wat &lt;Pho&gt;</name>"))
        XCTAssertTrue(kml.contains("<coordinates>100.4927,13.7465,0</coordinates>"))
        XCTAssertFalse(kml.contains("Empty"))
    }
}
