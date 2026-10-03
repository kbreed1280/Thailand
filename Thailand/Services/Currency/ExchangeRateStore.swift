import Foundation

struct ExchangeRate: Codable, Equatable {
    /// How many baht one US dollar buys.
    var thbPerUSD: Double
    /// When the provider last updated the rate (or when it was entered manually).
    var asOf: Date
    var source: String
    var isManual: Bool
}

/// Downloads, caches and serves the USD→THB rate. Works offline with the last saved rate.
@MainActor
final class ExchangeRateStore: ObservableObject {
    static let shared = ExchangeRateStore()

    @Published private(set) var rate: ExchangeRate?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let cacheKey = "exchangeRate.cache"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(ExchangeRate.self, from: data) {
            rate = cached
        }
    }

    /// The rate to use right now (cached, manual, or a rough fallback if nothing was ever saved).
    var thbPerUSD: Double { rate?.thbPerUSD ?? CurrencyMath.fallbackTHBPerUSD }

    var hasRealRate: Bool { rate != nil }

    /// Refreshes unless a manual rate is set or the cached rate is newer than `maxAge`.
    func refreshIfNeeded(maxAge: TimeInterval = 6 * 3600) async {
        if let rate, rate.isManual { return }
        if let rate, Date().timeIntervalSince(rate.asOf) < maxAge, rate.source != "fallback" { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var fresh = await fetchOpenER()
        if fresh == nil {
            fresh = await fetchFrankfurter()
        }
        if let fresh {
            store(fresh)
            lastError = nil
        } else {
            lastError = rate == nil
                ? "Couldn't download a rate. Using an estimate of ฿\(Int(CurrencyMath.fallbackTHBPerUSD)) per $1."
                : "Couldn't update — showing the last saved rate."
        }
    }

    func setManualRate(_ thbPerUSD: Double) {
        guard thbPerUSD > 0 else { return }
        store(ExchangeRate(thbPerUSD: thbPerUSD, asOf: .now, source: "Entered by you", isManual: true))
    }

    /// Drops the manual override and goes back to live rates.
    func clearManualRate() async {
        if rate?.isManual == true {
            rate = nil
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }
        await refresh()
    }

    private func store(_ newRate: ExchangeRate) {
        rate = newRate
        if let data = try? JSONEncoder().encode(newRate) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
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

    private func fetchOpenER() async -> ExchangeRate? {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD"),
              let response: OpenERResponse = await fetch(url),
              response.result == "success",
              let thb = response.rates["THB"], thb > 0 else { return nil }
        let asOf = response.time_last_update_unix.map(Date.init(timeIntervalSince1970:)) ?? .now
        return ExchangeRate(thbPerUSD: thb, asOf: asOf, source: "open.er-api.com", isManual: false)
    }

    private func fetchFrankfurter() async -> ExchangeRate? {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=THB"),
              let response: FrankfurterResponse = await fetch(url),
              let thb = response.rates["THB"], thb > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let asOf = formatter.date(from: response.date) ?? .now
        return ExchangeRate(thbPerUSD: thb, asOf: asOf, source: "frankfurter.app", isManual: false)
    }

    private func fetch<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
