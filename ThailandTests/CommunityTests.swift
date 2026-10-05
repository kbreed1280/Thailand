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
