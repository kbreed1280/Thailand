import XCTest
@testable import Thailand

final class FlightTests: XCTestCase {

    func testNormalize() {
        XCTAssertEqual(TrackedFlight.normalize("tg103"), "TG 103")
        XCTAssertEqual(TrackedFlight.normalize("FD-3205"), "FD 3205")
        XCTAssertEqual(TrackedFlight.normalize(" 3K 511 "), "3K 511")
        // A bare number has no airline code, so it must not be split into "70 1".
        XCTAssertEqual(TrackedFlight.normalize("701"), "701")
        XCTAssertFalse(TrackedFlight.isValidNumber("701"))
        XCTAssertTrue(TrackedFlight.isValidNumber("tg701"))
        XCTAssertNotNil(TrackedFlight.problem(with: "701"))
        XCTAssertNotNil(TrackedFlight.problem(with: "THA701"))
        XCTAssertNil(TrackedFlight.problem(with: "TG 701"))
    }

    func testParseAeroDataBoxResponse() throws {
        let json = """
        [{"number":"TG 103","status":"Delayed","airline":{"name":"Thai Airways"},"aircraft":{"model":"Airbus A320"},
          "departure":{"airport":{"iata":"BKK","shortName":"Suvarnabhumi","municipalityName":"Bangkok","timeZone":"Asia/Bangkok"},
                       "scheduledTime":{"utc":"2026-11-03 01:00Z","local":"2026-11-03 08:00+07:00"},
                       "revisedTime":{"utc":"2026-11-03 01:45Z","local":"2026-11-03 08:45+07:00"},
                       "terminal":"1","gate":"C4"},
          "arrival":{"airport":{"iata":"CNX","municipalityName":"Chiang Mai","timeZone":"Asia/Bangkok"},
                     "scheduledTime":{"utc":"2026-11-03 02:10Z","local":"2026-11-03 09:10+07:00"},"baggageBelt":"3"}}]
        """
        let flights = try FlightStatusService.parse(Data(json.utf8), fallbackNumber: "TG103")
        let flight = try XCTUnwrap(flights.first)
        XCTAssertEqual(flight.number, "TG 103")
        XCTAssertEqual(flight.airline, "Thai Airways")
        XCTAssertEqual(flight.departure.airportIATA, "BKK")
        XCTAssertEqual(flight.departure.gate, "C4")
        XCTAssertEqual(flight.departure.delayMinutes, 45)
        XCTAssertEqual(flight.arrival.baggageBelt, "3")
        XCTAssertEqual(flight.statusText, "Delayed")
    }

    func testChangeAlerts() {
        let base = FlightStatus(number: "TG 103", airline: nil, status: "Expected", aircraft: nil,
                                departure: FlightEndpoint(scheduled: Date(timeIntervalSince1970: 0), gate: "C4"),
                                arrival: FlightEndpoint(), fetchedAt: .now)
        var changed = base
        changed.departure.gate = "D2"
        changed.departure.revised = Date(timeIntervalSince1970: 40 * 60)
        let lines = FlightStore.changes(from: base, to: changed)
        XCTAssertTrue(lines.contains("Gate changed to D2 (was C4)"))
        XCTAssertTrue(lines.contains("Delayed 40 min"))
        XCTAssertTrue(FlightStore.changes(from: base, to: base).isEmpty)
    }

    func testDetectFlightsInBookingText() {
        let text = "Your booking: Thai AirAsia FD 3205 Bangkok (DMK) to Chiang Mai. Return flight tg115 on 12 Nov. Room 1205."
        XCTAssertEqual(FlightStore.detectFlights(in: text), ["FD 3205", "TG 115"])
    }

    func testPassportSixMonthRule() {
        let tripStart = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
        var passport = VaultDocument(title: "Passport", fileName: "x.jpg", kind: .image, category: .passport)
        passport.expiresAt = Calendar.current.date(byAdding: .month, value: 5, to: .now)
        if case .passportUnderSixMonths = passport.expiryWarning(tripStart: tripStart) {} else {
            XCTFail("Expected the 6-month passport warning")
        }
        passport.expiresAt = Calendar.current.date(byAdding: .year, value: 3, to: .now)
        XCTAssertNil(passport.expiryWarning(tripStart: tripStart))
    }
}

@MainActor
final class FlightOrderTests: XCTestCase {
    func testCustomOrderDecodesFromOldSaves() throws {
        // Flights saved before reordering existed have no sortIndex.
        let json = #"[{"id":"2B8AD509-6E3E-4B28-948F-4585B0331FF7","number":"TG 701","day":"2026-10-24","note":""}]"#
        let flights = try JSONDecoder().decode([TrackedFlight].self, from: Data(json.utf8))
        XCTAssertNil(flights[0].sortIndex)
    }
}
