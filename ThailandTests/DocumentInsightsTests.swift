import XCTest
@testable import Thailand

final class DocumentInsightsTests: XCTestCase {
    func testAmountsInBahtAndDollars() {
        let amounts = DocumentInsights.amounts(in: "Total ฿1,250.50 (approx $35.99). Deposit 500 baht, fee THB 80, tip 20 บาท, USD 12")
        XCTAssertTrue(amounts.contains(.init(value: 1_250.5, currency: .thb)))
        XCTAssertTrue(amounts.contains(.init(value: 35.99, currency: .usd)))
        XCTAssertTrue(amounts.contains(.init(value: 500, currency: .thb)))
        XCTAssertTrue(amounts.contains(.init(value: 80, currency: .thb)))
        XCTAssertTrue(amounts.contains(.init(value: 20, currency: .thb)))
        XCTAssertTrue(amounts.contains(.init(value: 12, currency: .usd)))
    }

    func testNoAmountsInPlainText() {
        XCTAssertTrue(DocumentInsights.amounts(in: "Room 1204, floor 12").isEmpty)
    }

    func testSuggestedTitleSkipsBoilerplate() {
        let text = """
        Booking confirmation
        Riverside Boutique Hotel Bangkok
        Check-in: 6 March
        """
        XCTAssertEqual(DocumentInsights.suggestedTitle(from: text), "Riverside Boutique Hotel Bangkok")
    }

    func testCategoryGuesses() {
        XCTAssertEqual(DocumentInsights.guessCategory("Check-in 14:00, 3 nights, deluxe room"), .hotel)
        XCTAssertEqual(DocumentInsights.guessCategory("Flight TG 102 boarding gate 5"), .transport)
        XCTAssertEqual(DocumentInsights.guessCategory("Thai cooking class with market tour"), .activity)
        XCTAssertEqual(DocumentInsights.guessCategory("Hello"), .place)
    }

    func testDetectsDatesPhonesAndLinks() {
        let text = "Tour on March 5, 2027 at 3:30 PM. Call +66 2 123 4567 or visit https://example.com/booking"
        let insights = DocumentInsights.analyze(text)
        XCTAssertFalse(insights.dates.isEmpty)
        XCTAssertTrue(insights.dates.contains { $0.hasTime })
        XCTAssertFalse(insights.phones.isEmpty)
        XCTAssertEqual(insights.links.first?.host, "example.com")
        XCTAssertEqual(insights.category, .activity)
    }
}
