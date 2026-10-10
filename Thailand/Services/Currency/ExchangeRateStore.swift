import Foundation

/// Exchange rates for every currency, relative to the US dollar, from one download.
struct RateTable: Codable, Equatable {
    /// Units of each currency per 1 USD ("THB": 33.1, "JPY": 149.2, "USD": 1).
    var perUSD: [String: Double]
    var asOf: Date
    var source: String

    /// How much `local` money one unit of `home` money buys.
    func rate(local: String, home: String) -> Double? {
        guard let l = perUSD[local.uppercased()], let h = perUSD[home.uppercased()], l > 0, h > 0 else { return nil }
        return l / h
    }
}

/// A rate you typed in (from a money-changer board or ATM receipt), for one currency pair.
struct ManualRate: Codable, Equatable {
    var local: String
    var home: String
    var localPerHome: Double
    var asOf: Date
}

/// What the converter shows: the rate, when it's from and where.
struct ExchangeRate: Equatable {
    var localPerHome: Double
    var asOf: Date
    var source: String
    var isManual: Bool
}

/// Downloads, caches and serves exchange rates for the selected trip's currency and your home
/// currency. Works offline with the last saved rates.
@MainActor
final class ExchangeRateStore: ObservableObject {
    static let shared = ExchangeRateStore()

    @Published private(set) var table: RateTable?
    @Published private(set) var manual: ManualRate?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    /// The trip's currency and your home currency (mirrors `CurrencyContext`, so views update).
    @Published private(set) var localCode = CurrencyContext.localCode
    @Published private(set) var homeCode = CurrencyContext.homeCode

    private let tableKey = "exchangeRates.table"
    private let manualKey = "exchangeRates.manual"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        if let data = UserDefaults.standard.data(forKey: tableKey), let cached = try? JSONDecoder().decode(RateTable.self, from: data) {
            table = cached
        }
        if let data = UserDefaults.standard.data(forKey: manualKey), let cached = try? JSONDecoder().decode(ManualRate.self, from: data) {
            manual = cached
        }
    }

    /// Switches the converter to a trip's currency (called when you pick or edit a trip).
    /// Also points the translator at the trip's language.
    func useTrip(_ trip: Trip) {
        setCurrencies(local: trip.localCurrency, home: CurrencyContext.homeCode)
        LocalLanguage.code = Destinations.language(forCountry: trip.country)
        CurrentDestination.country = trip.country
        CurrentDestination.coordinate = trip.destinationCoordinate
    }

    func setCurrencies(local: String, home: String) {
        CurrencyContext.localCode = local
        CurrencyContext.homeCode = home
        if localCode != local.uppercased() { localCode = local.uppercased() }
        if homeCode != home.uppercased() { homeCode = home.uppercased() }
    }

    private var manualForPair: ManualRate? {
        guard let manual, manual.local == localCode, manual.home == homeCode else { return nil }
        return manual
    }

    /// The rate in use right now.
    var rate: ExchangeRate? {
        if let m = manualForPair { return ExchangeRate(localPerHome: m.localPerHome, asOf: m.asOf, source: "Entered by you", isManual: true) }
        guard let table, let r = table.rate(local: localCode, home: homeCode) else { return nil }
        return ExchangeRate(localPerHome: r, asOf: table.asOf, source: table.source, isManual: false)
    }

    /// Local money per 1 unit of home money (1 if nothing has ever been downloaded for this pair).
    var localPerHome: Double { rate?.localPerHome ?? 1 }

    var hasRealRate: Bool { rate != nil }

    /// Refreshes unless a manual rate is set or the cached rates are newer than `maxAge`.
    func refreshIfNeeded(maxAge: TimeInterval = 6 * 3600) async {
        if manualForPair != nil { return }
        if let table, Date().timeIntervalSince(table.asOf) < maxAge, table.rate(local: localCode, home: homeCode) != nil { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var fresh = await fetchOpenER()
        if fresh == nil { fresh = await fetchFrankfurter() }
        if let fresh {
            table = fresh
            if let data = try? JSONEncoder().encode(fresh) { UserDefaults.standard.set(data, forKey: tableKey) }
            lastError = fresh.rate(local: localCode, home: homeCode) == nil ? "No live rate for \(localCode). Set one yourself." : nil
        } else {
            lastError = rate == nil
                ? "Couldn't download a rate. Set one yourself from a money changer or ATM receipt."
                : "Couldn't update — showing the last saved rate."
        }
    }

    func setManualRate(_ localPerHome: Double) {
        guard localPerHome > 0 else { return }
        let m = ManualRate(local: localCode, home: homeCode, localPerHome: localPerHome, asOf: .now)
        manual = m
        if let data = try? JSONEncoder().encode(m) { UserDefaults.standard.set(data, forKey: manualKey) }
    }

    /// Drops the manual override and goes back to live rates.
    func clearManualRate() async {
        manual = nil
        UserDefaults.standard.removeObject(forKey: manualKey)
        await refresh()
    }

    // MARK: Providers

    private struct OpenERResponse: Decodable {
        let result: String
        let rates: [String: Double]
        let time_last_update_unix: TimeInterval?
    }

    private struct FrankfurterResponse: Decodable {
        let rates: [String: Double]
        let date: String
    }

    private func fetchOpenER() async -> RateTable? {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD"),
              let response: OpenERResponse = await fetch(url),
              response.result == "success", !response.rates.isEmpty else { return nil }
        let asOf = response.time_last_update_unix.map(Date.init(timeIntervalSince1970:)) ?? .now
        return RateTable(perUSD: response.rates.merging(["USD": 1]) { a, _ in a }, asOf: asOf, source: "open.er-api.com")
    }

    private func fetchFrankfurter() async -> RateTable? {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD"),
              let response: FrankfurterResponse = await fetch(url), !response.rates.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let asOf = formatter.date(from: response.date) ?? .now
        return RateTable(perUSD: response.rates.merging(["USD": 1]) { a, _ in a }, asOf: asOf, source: "frankfurter.app")
    }

    private func fetch<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
