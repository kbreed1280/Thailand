import XCTest
@testable import Thailand

final class CurrencyMathTests: XCTestCase {

    // MARK: Conversion

    func testTHBToUSD() {
        XCTAssertEqual(CurrencyMath.convert(350, from: .thb, thbPerUSD: 35), 10, accuracy: 0.0001)
    }

    func testUSDToTHB() {
        XCTAssertEqual(CurrencyMath.convert(12.5, from: .usd, thbPerUSD: 33.2), 415, accuracy: 0.0001)
    }

    func testRoundTripIsStable() {
        let rate = 32.87
        let usd = CurrencyMath.convert(1_000, from: .thb, thbPerUSD: rate)
        XCTAssertEqual(CurrencyMath.convert(usd, from: .usd, thbPerUSD: rate), 1_000, accuracy: 0.0001)
    }

    func testZeroOrNegativeRateReturnsZero() {
        XCTAssertEqual(CurrencyMath.convert(100, from: .thb, thbPerUSD: 0), 0)
        XCTAssertEqual(CurrencyMath.convert(100, from: .usd, thbPerUSD: -3), 0)
    }

    // MARK: Parsing

    func testParsePlainAndSymbols() {
        XCTAssertEqual(CurrencyMath.parseAmount("500"), 500)
        XCTAssertEqual(CurrencyMath.parseAmount("฿500"), 500)
        XCTAssertEqual(CurrencyMath.parseAmount("$12.50"), 12.5)
        XCTAssertEqual(CurrencyMath.parseAmount("  42 "), 42)
    }

    func testParseThousandsSeparators() {
        XCTAssertEqual(CurrencyMath.parseAmount("1,000"), 1_000)
        XCTAssertEqual(CurrencyMath.parseAmount("12,345.67"), 12_345.67)
        XCTAssertEqual(CurrencyMath.parseAmount("1 000"), 1_000)
    }

    func testParseCommaDecimal() {
        XCTAssertEqual(CurrencyMath.parseAmount("12,50"), 12.5)
        XCTAssertEqual(CurrencyMath.parseAmount("1.234,5"), 1_234.5)
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(CurrencyMath.parseAmount(""))
        XCTAssertNil(CurrencyMath.parseAmount("abc"))
        XCTAssertNil(CurrencyMath.parseAmount("-5"))
    }

    // MARK: Formatting

    func testFormatting() {
        XCTAssertTrue(CurrencyMath.format(1_000, .thb).hasPrefix("฿"))
        XCTAssertFalse(CurrencyMath.format(1_000, .thb).contains("."))
        XCTAssertTrue(CurrencyMath.format(3.4, .usd).hasSuffix("40"))
        XCTAssertEqual(CurrencyMath.roundedToCents(1.005 + 0.0001), 1.01)
    }

    // MARK: Tip & split

    func testTipAndSplit() {
        XCTAssertEqual(CurrencyMath.tip(on: 1_000, percent: 10), 100)
        XCTAssertEqual(CurrencyMath.perPerson(bill: 1_000, tipPercent: 10, people: 2), 550)
        XCTAssertEqual(CurrencyMath.perPerson(bill: 100, tipPercent: 0, people: 3), 33.33)
        XCTAssertEqual(CurrencyMath.perPerson(bill: 100, tipPercent: 10, people: 0), 0)
    }

    // MARK: Expenses

    func testEqualSplitBetweenTwo() {
        let shares = [
            CurrencyMath.Share(amount: 400, paidBy: "Alex", split: .equal),
            CurrencyMath.Share(amount: 1_000, paidBy: "Sam", split: .equal)
        ]
        let balances = CurrencyMath.balances(for: shares, participants: ["Alex", "Sam"])
        XCTAssertEqual(balances["Alex"], -300)
        XCTAssertEqual(balances["Sam"], 300)
        XCTAssertEqual(CurrencyMath.settlements(for: balances), [.init(from: "Alex", to: "Sam", amount: 300)])
    }

    func testPayerOnlyDoesNotCreateDebt() {
        let shares = [CurrencyMath.Share(amount: 500, paidBy: "Alex", split: .payerOnly)]
        let balances = CurrencyMath.balances(for: shares, participants: ["Alex", "Sam"])
        XCTAssertEqual(balances["Alex"], 0)
        XCTAssertEqual(balances["Sam"], 0)
        XCTAssertTrue(CurrencyMath.settlements(for: balances).isEmpty)
    }

    func testCustomSplit() {
        // Alex pays 1,000 and covers 70% of it; Sam owes the other 30%.
        let shares = [CurrencyMath.Share(amount: 1_000, paidBy: "Alex", split: .custom, payerShare: 0.7)]
        let balances = CurrencyMath.balances(for: shares, participants: ["Alex", "Sam"])
        XCTAssertEqual(balances["Alex"], 300)
        XCTAssertEqual(balances["Sam"], -300)
    }

    func testBalancesAlwaysSumToZero() {
        let shares = [
            CurrencyMath.Share(amount: 333, paidBy: "A", split: .equal),
            CurrencyMath.Share(amount: 120, paidBy: "B", split: .custom, payerShare: 0.25),
            CurrencyMath.Share(amount: 75, paidBy: "C", split: .equal)
        ]
        let balances = CurrencyMath.balances(for: shares, participants: ["A", "B", "C"])
        XCTAssertEqual(balances.values.reduce(0, +), 0, accuracy: 0.02)
        let transfers = CurrencyMath.settlements(for: balances)
        let paidOut = transfers.reduce(0) { $0 + $1.amount }
        let owed = balances.values.filter { $0 > 0 }.reduce(0, +)
        XCTAssertEqual(paidOut, owed, accuracy: 0.02)
    }

    func testSinglePersonHasNoBalances() {
        let shares = [CurrencyMath.Share(amount: 200, paidBy: "Me", split: .equal)]
        let balances = CurrencyMath.balances(for: shares, participants: ["Me"])
        XCTAssertEqual(balances["Me"], 0)
    }

    func testPayerNotInParticipantsIsAdded() {
        let shares = [CurrencyMath.Share(amount: 200, paidBy: "Guest", split: .equal)]
        let balances = CurrencyMath.balances(for: shares, participants: ["Me"])
        XCTAssertEqual(balances["Guest"], 100)
        XCTAssertEqual(balances["Me"], -100)
    }
}
