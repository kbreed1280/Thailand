import XCTest
import CoreLocation
@testable import Thailand

final class BangkokRailTests: XCTestCase {
    private let rail = BangkokRail.shared

    private func station(_ code: String) -> RailStation {
        rail.allStations.first { $0.station.code == code }!.station
    }

    func testNetworkLoads() {
        XCTAssertEqual(rail.lines.count, 9)
        XCTAssertEqual(rail.lines.first { $0.id == "bts-sukhumvit" }?.stations.count, 47)
        XCTAssertEqual(rail.lines.first { $0.id == "mrt-blue" }?.stations.count, 38)
        XCTAssertEqual(station("CEN").en, "Siam")
        XCTAssertEqual(station("A1").en, "Suvarnabhumi")
    }

    func testSiamToAsokIsOneRideOnSukhumvit() throws {
        let journey = try XCTUnwrap(rail.journey(from: station("CEN").coordinate, to: station("E4").coordinate))
        XCTAssertEqual(journey.rides.count, 1)
        XCTAssertEqual(journey.rides[0].line.id, "bts-sukhumvit")
        XCTAssertEqual(journey.rides[0].stops, 4)
        XCTAssertEqual(journey.rides[0].terminus.en, "Kheha")
    }

    func testAirportToSilomChangesLines() throws {
        // Suvarnabhumi → Sala Daeng: Airport Link, then BTS (or MRT via Makkasan).
        let journey = try XCTUnwrap(rail.journey(from: station("A1").coordinate, to: station("S2").coordinate))
        XCTAssertEqual(journey.rides.first?.line.id, "arl")
        XCTAssertGreaterThanOrEqual(journey.transfers, 1)
        XCTAssertGreaterThan(journey.fareTHB, 30)
        XCTAssertLessThan(journey.totalMinutes, 90)
    }

    func testBlueLineLoopUsesThaPhraJunction() throws {
        // Itsaraphap (BL32) → Bang Phai (BL33) goes through Tha Phra, not a direct link.
        let journey = try XCTUnwrap(rail.journey(from: station("BL32").coordinate, to: station("BL35").coordinate, maxWalkMeters: 300))
        let codes = journey.rides.flatMap { $0.stations.map(\.code) }
        XCTAssertTrue(codes.contains("BL01"), "\(codes)")
    }

    func testShortHopPrefersWalking() {
        // Phloen Chit → Chit Lom is ~600 m: no rail suggestion.
        XCTAssertNil(rail.journey(from: station("E2").coordinate, to: station("E1").coordinate))
    }

    func testOutsideBangkokHasNoRoute() {
        let chiangMai = CLLocationCoordinate2D(latitude: 18.7883, longitude: 98.9853)
        XCTAssertFalse(BangkokRail.covers(chiangMai))
        XCTAssertNil(rail.journey(from: chiangMai, to: station("CEN").coordinate))
    }

    func testNearestStationToMBK() {
        let mbk = CLLocationCoordinate2D(latitude: 13.7447, longitude: 100.5300)
        XCTAssertEqual(rail.nearestStations(to: mbk, limit: 1).first?.station.en, "National Stadium")
    }
}
