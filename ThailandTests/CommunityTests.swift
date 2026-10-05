import CoreLocation
import XCTest
@testable import Thailand

final class CommunityTests: XCTestCase {
    private func tip(_ key: String = "apple:jayfai", source: String, install: String = UUID().uuidString,
                     order: String = "", rec: String = "", creator: String = "") -> CommunityTip {
        CommunityTip(placeKey: key, name: "Jay Fai", latitude: 13.7525, longitude: 100.5048, category: "eat", city: "Bangkok",
                     recommendation: rec, whatToOrder: order, sourceURL: source, creator: creator, contributor: "", installID: install)
    }

    func testTipShownOnlyWhenSourcesAgree() {
        let places = CommunityAggregator.aggregate([
            tip(source: "https://tiktok.com/1", order: "crab omelette, drunken noodles", rec: "The crab omelette is worth the wait", creator: "@foodie"),
            tip(source: "https://youtube.com/2", order: "Crab Omelette and tom yum", creator: "Mark Wiens"),
            tip(source: "https://tiktok.com/3", order: "pad thai"),
        ])
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].sourceCount, 3)
        XCTAssertEqual(places[0].agreedOrders, ["crab omelette"], "only the dish 2+ sources named")
        XCTAssertEqual(places[0].agreedTip, "The crab omelette is worth the wait")
        XCTAssertEqual(places[0].credits, ["@foodie", "Mark Wiens"])
    }

    func testOneSourceRepeatedDoesNotCountTwice() {
        let same = "https://tiktok.com/1"
        let places = CommunityAggregator.aggregate([
            tip(source: same, order: "crab omelette"), tip(source: same, order: "crab omelette"),
        ])
        XCTAssertEqual(places[0].sourceCount, 1)
        XCTAssertTrue(places[0].agreedOrders.isEmpty)
        XCTAssertNil(places[0].agreedTip)
    }

    func testTrendingNeedsAgreementAndDistance() {
        let near = CLLocationCoordinate2D(latitude: 13.75, longitude: 100.50)
        let tips = [tip(source: "a"), tip(source: "b"), tip("apple:solo", source: "c")]
        XCTAssertEqual(CommunityAggregator.trending(tips, near: near).map(\.placeKey), ["apple:jayfai"])
        XCTAssertTrue(CommunityAggregator.trending(tips, near: .init(latitude: 18.79, longitude: 98.98)).isEmpty, "Chiang Mai is far")
    }

    func testPeopleWithoutAPostCountByInstall() {
        let places = CommunityAggregator.aggregate([tip(source: "", install: "A"), tip(source: "", install: "A"), tip(source: "", install: "B")])
        XCTAssertEqual(places[0].sourceCount, 2)
    }

    func testCellsCoverNeighbors() {
        let c = CLLocationCoordinate2D(latitude: 13.7525, longitude: 100.5048)
        XCTAssertTrue(CommunityAggregator.cells(around: c).contains(CommunityAggregator.cell(.init(latitude: 13.79, longitude: 100.54))))
        XCTAssertEqual(CommunityAggregator.cells(around: c).count, 9)
    }
}

final class ImportQuotaTests: XCTestCase {
    func testDailyLimitResetsNextDay() {
        let cal = Calendar.current
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        var q = ImportQuota()
        for _ in 0..<5 { XCTAssertTrue(q.consume(limit: 5, now: today)) }
        XCTAssertFalse(q.consume(limit: 5, now: today))
        XCTAssertEqual(q.remaining(limit: 5, now: today), 0)
        XCTAssertEqual(q.remaining(limit: 5, now: tomorrow), 5)
        XCTAssertTrue(q.consume(limit: 5, now: tomorrow))
        XCTAssertEqual(q.remaining(limit: 5, now: tomorrow), 4)
    }
}

final class PlacePhotosTests: XCTestCase {
    func testPicksMatchingNearbyArticle() {
        let json = """
        {"query":{"pages":{
          "1":{"title":"Wat Phra Kaew","thumbnail":{"source":"https://upload.wikimedia.org/a.jpg"}},
          "2":{"title":"Sanam Luang","thumbnail":{"source":"https://upload.wikimedia.org/b.jpg"}},
          "3":{"title":"Grand Palace"}
        }}}
        """.data(using: .utf8)!
        XCTAssertEqual(PlacePhotos.bestPhoto(in: json, for: "Wat Phra Kaew")?.lastPathComponent, "a.jpg")
        XCTAssertNil(PlacePhotos.bestPhoto(in: json, for: "Grand Palace"), "no thumbnail")
        XCTAssertNil(PlacePhotos.bestPhoto(in: json, for: "Jay Fai"), "no matching article")
    }
}

final class DiscoverFilterTests: XCTestCase {
    private func l(_ title: String, _ desc: String?, image: Bool = true) -> Landmark {
        Landmark(id: Int.random(in: 1...999_999), title: title, summary: "", shortDescription: desc,
                 imageURL: image ? URL(string: "https://upload.wikimedia.org/x.jpg") : nil, latitude: 13.75, longitude: 100.5)
    }

    func testKeepsSightsDropsAdministrativeAndPhotoless() {
        XCTAssertTrue(DiscoverFilter.isInteresting(l("Wat Arun", "Buddhist temple in Bangkok")))
        XCTAssertTrue(DiscoverFilter.isInteresting(l("Chatuchak Weekend Market", "market in Bangkok")))
        XCTAssertFalse(DiscoverFilter.isInteresting(l("Bang Rak District", "district of Bangkok")))
        XCTAssertFalse(DiscoverFilter.isInteresting(l("Silom Road", "road in Bangkok")))
        XCTAssertFalse(DiscoverFilter.isInteresting(l("Sala Daeng BTS station", "Skytrain station")))
        XCTAssertFalse(DiscoverFilter.isInteresting(l("Wat Pho", "temple", image: false)), "needs a photo")
    }
}

@MainActor
final class TopPicksTests: XCTestCase {
    func testBangkokPicksLoadWithLocationsAndPhotos() {
        let picks = TopPicks.bangkok
        XCTAssertGreaterThanOrEqual(picks.count, 35)
        let located = picks.filter { $0.coordinate != nil }
        XCTAssertGreaterThanOrEqual(located.count, 35)
        for p in located {
            let c = p.coordinate!
            XCTAssertTrue((13.4...14.0).contains(c.latitude) && (99.8...100.8).contains(c.longitude), "\(p.name) is near Bangkok")
        }
        XCTAssertGreaterThanOrEqual(picks.filter { $0.photoURL != nil }.count, 30)
        XCTAssertEqual(Set(picks.compactMap { $0.landmark?.id }).count, located.count, "unique ids")
        XCTAssertTrue(picks.contains { $0.name == "Wat Pho (Reclining Buddha)" && $0.spotCategory == .explore })
        XCTAssertTrue(picks.contains { $0.name == "Jay Fai" && $0.spotCategory == .eat })
    }

    func testSaveAllCreatesListWithPhotos() {
        let context = PersistenceController(inMemory: true).viewContext
        let trip = ItineraryStore(context: context).createTrip(name: "BKK", start: .now, end: .now.addingTimeInterval(86_400))
        UserDefaults.standard.set(trip.uuid?.uuidString, forKey: AppSettings.selectedTripKey)
        let picks = Array(TopPicks.bangkok.filter { $0.coordinate != nil }.prefix(5))
        let list = TopPicks.saveAll(picks, to: trip, context: context)
        XCTAssertEqual(list.spots.count, 5)
        XCTAssertEqual(list.displayName, "Bangkok Top Picks")
        XCTAssertTrue(list.spots.allSatisfy { $0.status == .confirmed })
        // Saving again doesn't duplicate.
        _ = TopPicks.saveAll(picks, to: trip, context: context)
        XCTAssertEqual(trip.confirmedSpots.count, 5)
    }
}
