import XCTest
@testable import Thailand

final class TripBuilderTests: XCTestCase {
    func testWishesSplitIntoSearches() {
        XCTAssertEqual(DestinationIdeas.phrases(in: "I love ramen, jazz bars and art museums"), ["ramen", "jazz bars", "art museums"])
        XCTAssertEqual(DestinationIdeas.phrases(in: "lots of street food & a sunset viewpoint"), ["street food", "a sunset viewpoint"])
    }

    func testLongOrTinyPhrasesAreDropped() {
        XCTAssertEqual(DestinationIdeas.phrases(in: "ok, somewhere quiet where we can sit for hours reading"), [])
    }

    func testSearchesAreDeduplicatedAndCapped() {
        let cleaned = DestinationIdeas.clean(["Ramen", "ramen ", "", "jazz bar"] + (1...20).map { "thing \($0)" })
        XCTAssertEqual(cleaned.prefix(2), ["ramen", "jazz bar"])
        XCTAssertEqual(cleaned.count, 10)
    }

    func testFallbackUsesVibeWhenNoWishes() async {
        let result = await DestinationIdeas.searches(for: "", destination: "Lisbon", vibe: .nightlife)
        XCTAssertFalse(result.usedAI)
        XCTAssertEqual(result.searches, AutoPlanner.Vibe.nightlife.fillQueries)
    }
}

final class EntryRequirementsTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    func testPassportChecks() {
        let end = date(2026, 11, 14)
        XCTAssertEqual(EntryRequirements.passportStatus(expires: nil, tripEnd: end, calendar: cal), .unknown)
        XCTAssertEqual(EntryRequirements.passportStatus(expires: date(2026, 11, 1), tripEnd: end, calendar: cal), .expiresDuringTrip(date(2026, 11, 1)))
        XCTAssertEqual(EntryRequirements.passportStatus(expires: date(2027, 3, 1), tripEnd: end, calendar: cal), .underSixMonths(date(2027, 3, 1)))
        XCTAssertEqual(EntryRequirements.passportStatus(expires: date(2028, 1, 1), tripEnd: end, calendar: cal), .ok(date(2028, 1, 1)))
    }

    func testFormsByCountry() {
        XCTAssertEqual(EntryRequirements.forms(forCountry: "th").first?.url.host(), "tdac.immigration.go.th")
        XCTAssertEqual(EntryRequirements.forms(forCountry: "GB").first?.name, "UK Electronic Travel Authorisation (ETA)")
        XCTAssertEqual(EntryRequirements.forms(forCountry: "FR").first?.name, "EU Entry/Exit System (EES)")
        XCTAssertTrue(EntryRequirements.forms(forCountry: "ZZ").isEmpty)
        // Every link is HTTPS.
        for code in ["TH", "GB", "SG", "MY", "PH", "ID", "JP", "KR", "TW", "VN", "KH", "IN", "LK", "AU", "NZ", "CA", "US", "TR", "EG", "KE", "IT"] {
            XCTAssertTrue(EntryRequirements.forms(forCountry: code).allSatisfy { $0.url.scheme == "https" }, code)
        }
    }
}
