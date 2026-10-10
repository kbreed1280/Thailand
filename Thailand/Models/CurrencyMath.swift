import Foundation

/// The two currencies the app converts between: the selected trip's local money and your own.
enum Currency: String, CaseIterable, Identifiable {
    case local
    case home

    var id: String { rawValue }
    /// ISO code right now ("JPY", "USD").
    var code: String { self == .local ? CurrencyContext.localCode : CurrencyContext.homeCode }
    var symbol: String { CurrencyContext.symbol(code) }
    var name: String { CurrencyContext.name(code) }
    var flag: String { CurrencyContext.flag(code) }
    var other: Currency { self == .local ? .home : .local }
}

/// Pure money math, unit-tested in `CurrencyMathTests`.
enum CurrencyMath {
    /// Converts between local and home money given how much local money one unit of home money buys.
    static func convert(_ amount: Double, from source: Currency, localPerHome rate: Double) -> Double {
        guard rate > 0, amount.isFinite else { return 0 }
        switch source {
        case .local: return amount / rate
        case .home: return amount * rate
        }
    }

    /// Parses what people type: "1,000", "1 000", "฿500", "$12.50", "12,50" (comma decimal).
    static func parseAmount(_ text: String) -> Double? {
        var cleaned = text
            .replacingOccurrences(of: "฿", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: CurrencyContext.symbol(CurrencyContext.localCode).trimmingCharacters(in: .whitespaces), with: "")
            .replacingOccurrences(of: CurrencyContext.symbol(CurrencyContext.homeCode).trimmingCharacters(in: .whitespaces), with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let commas = cleaned.filter { $0 == "," }.count
        let dots = cleaned.filter { $0 == "." }.count
        if commas > 0 && dots > 0 {
            // Whichever separator comes last is the decimal point.
            if let lastComma = cleaned.lastIndex(of: ","), let lastDot = cleaned.lastIndex(of: "."), lastComma > lastDot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if commas == 1, let comma = cleaned.firstIndex(of: ",") {
            // "12,50" is a decimal; "1,000" is thousands.
            let decimals = cleaned.distance(from: comma, to: cleaned.endIndex) - 1
            cleaned = decimals == 3
                ? cleaned.replacingOccurrences(of: ",", with: "")
                : cleaned.replacingOccurrences(of: ",", with: ".")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        }

        guard let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// "฿1,234" / "¥1,500" / "€12.50" / "$3.41". Local money shows decimals only when there are some
    /// (and never for currencies without them, like yen).
    static func format(_ amount: Double, _ currency: Currency) -> String {
        let digits = CurrencyContext.fractionDigits(currency.code)
        let fraction: ClosedRange<Int> = digits == 0 ? 0...0 : currency == .home ? digits...digits : (amount.rounded() == amount ? 0...0 : digits...digits)
        let number = amount.formatted(.number.precision(.fractionLength(fraction)).grouping(.automatic))
        return "\(currency.symbol)\(number)"
    }

    /// Rounds to cents / satang.
    static func roundedToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    // MARK: Tip & split

    static func tip(on bill: Double, percent: Double) -> Double {
        roundedToCents(max(bill, 0) * max(percent, 0) / 100)
    }

    // MARK: Shared expenses

    struct Share {
        var amount: Double
        var paidBy: String
        var split: ExpenseSplit
        /// Payer's own fraction (0...1) for `.custom`.
        var payerShare: Double = 0.5
    }

    struct Transfer: Equatable {
        var from: String
        var to: String
        var amount: Double
    }

    /// Net balance per person: positive means others owe them, negative means they owe.
    static func balances(for shares: [Share], participants: [String]) -> [String: Double] {
        var people = participants
        for share in shares where !people.contains(share.paidBy) {
            people.append(share.paidBy)
        }
        var balance = Dictionary(uniqueKeysWithValues: people.map { ($0, 0.0) })
        guard people.count > 1 else { return balance }

        for share in shares where share.amount > 0 {
            let others = people.filter { $0 != share.paidBy }
            let othersOwe: Double
            switch share.split {
            case .payerOnly:
                othersOwe = 0
            case .equal:
                othersOwe = share.amount * Double(others.count) / Double(people.count)
            case .custom:
                othersOwe = share.amount * (1 - min(max(share.payerShare, 0), 1))
            }
            guard othersOwe > 0, !others.isEmpty else { continue }
            balance[share.paidBy, default: 0] += othersOwe
            let each = othersOwe / Double(others.count)
            for person in others {
                balance[person, default: 0] -= each
            }
        }
        return balance.mapValues(roundedToCents)
    }

    /// Fewest simple payments that settle everyone up (greedy largest debtor → largest creditor).
    static func settlements(for balances: [String: Double]) -> [Transfer] {
        var creditors = balances.filter { $0.value > 0.004 }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        var debtors = balances.filter { $0.value < -0.004 }.map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 }
        var transfers: [Transfer] = []
        var c = 0, d = 0
        while c < creditors.count && d < debtors.count {
            let amount = min(creditors[c].1, debtors[d].1)
            transfers.append(Transfer(from: debtors[d].0, to: creditors[c].0, amount: roundedToCents(amount)))
            creditors[c].1 -= amount
            debtors[d].1 -= amount
            if creditors[c].1 < 0.005 { c += 1 }
            if debtors[d].1 < 0.005 { d += 1 }
        }
        return transfers
    }
}
