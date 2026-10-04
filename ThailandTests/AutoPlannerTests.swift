import CoreLocation
import XCTest
@testable import Thailand

final class AutoPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }()
    private lazy var day1 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
    private lazy var day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

    private func stop(_ name: String, _ lat: Double, _ lon: Double, _ category: SpotCategory) -> AutoPlanner.Stop {
        AutoPlanner.Stop(id: UUID(), name: name, coordinate: .init(latitude: lat, longitude: lon), category: category)
    }

    // Old Town (Rattanakosin) vs. Sukhumvit, ~8 km apart.
    private lazy var oldTown = [
        stop("Wat Pho", 13.7465, 100.4927, .explore),
        stop("Grand Palace", 13.7500, 100.4913, .explore),
        stop("Jay Fai", 13.7525, 100.5048, .eat),
        stop("Brick Bar", 13.7590, 100.4970, .sip),
    ]
    private lazy var sukhumvit = [
        stop("Roots Coffee", 13.7305, 100.5690, .brew),
        stop("Octave Rooftop", 13.7235, 100.5810, .sip),
        stop("EmQuartier", 13.7318, 100.5697, .vibe),
        stop("Soul Food Mahanakorn", 13.7240, 100.5790, .eat),
    ]

    func testNearbySpotsShareADay() {
        let plan = AutoPlanner.plan(oldTown + sukhumvit, dates: [day1, day2], pace: .balanced, calendar: calendar)
        XCTAssertEqual(plan.days.count, 2)
        XCTAssertTrue(plan.leftOver.isEmpty)
        for day in plan.days {
            let names = Set(day.stops.map(\.stop.name))
            XCTAssertTrue(names == Set(oldTown.map(\.name)) || names == Set(sukhumvit.map(\.name)), "\(names)")
        }
    }

    func testDayIsOrderedAroundTheHeat() {
        let plan = AutoPlanner.plan(sukhumvit, dates: [day1], pace: .balanced, calendar: calendar)
        let order = plan.days[0].stops.map(\.stop.category)
        XCTAssertEqual(order.first, .brew, "coffee first")
        XCTAssertEqual(order.last, .sip, "rooftop bar last")
        let starts = plan.days[0].stops.map(\.start)
        XCTAssertEqual(starts, starts.sorted(), "times increase")
        XCTAssertEqual(calendar.component(.hour, from: starts[0]), 8)
        XCTAssertGreaterThanOrEqual(calendar.component(.hour, from: starts.last!), 18, "bar after sunset")
    }

    func testTemplesGoInTheMorningAndSecondMealIsDinner() {
        let day = [stop("Wat Arun", 13.7437, 100.4889, .explore),
                   stop("Lunch", 13.7440, 100.4900, .eat),
                   stop("Dinner", 13.7445, 100.4910, .eat)]
        let stops = AutoPlanner.plan(day, dates: [day1], pace: .balanced, calendar: calendar).days[0].stops
        XCTAssertEqual(stops.first?.stop.name, "Wat Arun")
        XCTAssertLessThan(calendar.component(.hour, from: stops[0].start), 12)
        XCTAssertGreaterThanOrEqual(calendar.component(.hour, from: stops[2].start), 18)
    }

    func testLunchIsntPushedLateByManySights() {
        let day = [stop("Grand Palace", 13.7500, 100.4913, .explore), stop("Wat Pho", 13.7465, 100.4927, .explore),
                   stop("Wat Arun", 13.7437, 100.4889, .explore), stop("Lunch", 13.7460, 100.4930, .eat)]
        let stops = AutoPlanner.plan(day, dates: [day1], pace: .balanced, calendar: calendar).days[0].stops
        let lunch = stops.first { $0.stop.name == "Lunch" }!
        XCTAssertLessThan(calendar.component(.hour, from: lunch.start), 14)
        XCTAssertEqual(stops.last?.stop.category, .explore, "third sight after lunch")
    }

    func testPaceCapsStopsAndReportsLeftOvers() {
        let plan = AutoPlanner.plan(oldTown + sukhumvit, dates: [day1], pace: .relaxed, calendar: calendar)
        XCTAssertEqual(plan.days[0].stops.count, 3)
        XCTAssertEqual(plan.leftOver.count, 5)
    }

    func testGapsSuggestAMealWhenADayHasNone() {
        let plan = AutoPlanner.plan([stop("Wat Pho", 13.7465, 100.4927, .explore)], dates: [day1], pace: .balanced, calendar: calendar)
        XCTAssertEqual(plan.days[0].gaps, [.eat])
    }

    func testHotDayMovesShoppingIntoMiddayHeat() {
        XCTAssertEqual(AutoPlanner.slot(for: .vibe, hot: true), .midday)
        XCTAssertEqual(AutoPlanner.slot(for: .vibe, hot: false), .afternoon)
    }
}

final class DayReminderTests: XCTestCase {
    func testRemindsTheEveningBeforeEachPlannedDay() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let d3 = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: d2)!
        let list = DayReminders.reminders(for: [(d2, [("Wat Pho", nine), ("Jay Fai", nil)]), (d3, [])],
                                          weather: { _ in "High 34°C." }, now: now, calendar: cal)
        XCTAssertEqual(list.count, 1, "empty days get no reminder")
        XCTAssertEqual(cal.component(.hour, from: list[0].fireDate), 20)
        XCTAssertEqual(cal.component(.day, from: list[0].fireDate), 1)
        XCTAssertTrue(list[0].body.hasPrefix("2 stops, starting"))
        XCTAssertTrue(list[0].body.contains("Wat Pho"))
        XCTAssertTrue(list[0].body.hasSuffix("High 34°C."))
    }

    func testPastEveningsAreSkipped() {
        let cal = Calendar.current
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 21))!
        XCTAssertTrue(DayReminders.reminders(for: [(d, [("A", nil)])], now: now, calendar: cal).isEmpty)
    }
}
