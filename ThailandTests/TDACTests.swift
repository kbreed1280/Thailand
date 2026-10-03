import XCTest
@testable import Thailand

final class TDACTests: XCTestCase {
    private let bangkok = TimeZone(identifier: "Asia/Bangkok")!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func flight(_ number: String, arrivingAt airport: String, on arrival: Date) -> TrackedFlight {
        var f = TrackedFlight(number: number, day: "2026-10-23")
        f.status = FlightStatus(number: number, status: "Expected",
                                departure: FlightEndpoint(airportIATA: "LAX"),
                                arrival: FlightEndpoint(airportIATA: airport, scheduled: arrival),
                                fetchedAt: .now)
        return f
    }

    func testUsesTripStartWhenNoFlight() {
        let start = date(2026, 10, 24, 0, tz: bangkok)
        let w = TDACReminder.window(tripStart: start, flights: [])!
        XCTAssertEqual(w.arrival, date(2026, 10, 24, 12, tz: bangkok))
        XCTAssertEqual(w.opens, date(2026, 10, 21, 12, tz: bangkok)) // 72 h before
        XCTAssertEqual(w.source, "your trip start date")
    }

    func testPrefersFlightLandingInThailand() {
        let landing = date(2026, 10, 24, 23, tz: bangkok)
        let connecting = flight("NH 6", arrivingAt: "NRT", on: date(2026, 10, 24, 15, tz: bangkok))
        let toBangkok = flight("TG 641", arrivingAt: "BKK", on: landing)
        let w = TDACReminder.window(tripStart: date(2026, 10, 24, 0, tz: bangkok), flights: [connecting, toBangkok])!
        XCTAssertEqual(w.arrival, landing)
        XCTAssertEqual(w.opens, landing.addingTimeInterval(-72 * 3600))
        XCTAssertEqual(w.source, "your flight TG 641")
    }

    func testStatus() {
        let arrival = Date().addingTimeInterval(5 * 86_400)
        let w = TDACReminder.Window(arrival: arrival, opens: arrival.addingTimeInterval(-72 * 3600), source: "")
        XCTAssertEqual(w.status(), .notYet)
        XCTAssertEqual(w.status(now: arrival.addingTimeInterval(-3600)), .open)
        XCTAssertEqual(w.status(now: arrival.addingTimeInterval(3600)), .passed)
    }

    func testNoDatesNoWindow() {
        XCTAssertNil(TDACReminder.window(tripStart: nil, flights: []))
    }
}
