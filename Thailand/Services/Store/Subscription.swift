import Foundation
import StoreKit

/// Free plan: a few imports a day. WanderHub Pro (StoreKit 2): $4.99/month with a 3-day free
/// trial, or $49.99/year. Unlocked only in Xcode (debug) builds. TestFlight and App Review use
/// the sandbox, where purchases are free, so reviewers can test buying.
///
/// App Store Connect setup: subscription group "WanderHub Pro" with
/// `com.kbreed.thailandtrip.pro.monthly` ($4.99, introductory offer: free for 3 days) and
/// `com.kbreed.thailandtrip.pro.yearly` ($49.99).
@MainActor
final class Subscription: ObservableObject {
    static let shared = Subscription()

    static let productIDs = ["com.kbreed.thailandtrip.pro.monthly", "com.kbreed.thailandtrip.pro.yearly"]
    static let freeImportsPerDay = 5

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isTestBuild = false
    @Published private(set) var purchasing = false
    @Published var message: String?
    /// Whether this Apple Account can still get each plan's free trial.
    @Published private(set) var trialEligible: [String: Bool] = [:]

    var monthly: Product? { products.first { $0.id == Self.productIDs[0] } }
    var yearly: Product? { products.first { $0.id == Self.productIDs[1] } }

    /// "3-day free trial" if this plan has one and you haven't used it.
    func trialText(for product: Product) -> String? {
        guard trialEligible[product.id] == true, let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        let unit = switch p.unit { case .day: "day"; case .week: "week"; case .month: "month"; case .year: "year"; @unknown default: "day" }
        return "\(p.value)-\(unit) free trial"
    }

    /// Yearly saving vs. paying monthly, e.g. 17.
    var yearlySavingsPercent: Int? {
        guard let m = monthly, let y = yearly, m.price > 0 else { return nil }
        let twelve = m.price * 12
        let pct = NSDecimalNumber(decimal: (twelve - y.price) / twelve * 100).doubleValue
        return pct >= 1 ? Int(pct.rounded()) : nil
    }

    var isUnlocked: Bool { isPro || isTestBuild }

    private var updates: Task<Void, Never>?

    private init() {
        #if DEBUG
        isTestBuild = true
        #endif
    }

    func start() async {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refreshEntitlements()
            }
        }
        await refreshEntitlements()
        products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price }
        for product in products {
            trialEligible[product.id] = await product.subscription?.isEligibleForIntroOffer ?? false
        }
    }

    func refreshEntitlements() async {
        var pro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil { pro = true }
        }
        isPro = pro
    }

    func purchase(_ product: Product) async {
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let t) = result { await t.finish() }
                await refreshEntitlements()
            case .pending: message = "Waiting for approval."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
        message = isPro ? "Pro restored." : "No subscription found for this Apple Account."
    }

    // MARK: Daily import quota

    private static let quotaKey = "importQuota"

    var importsLeftToday: Int {
        isUnlocked ? .max : ImportQuota.load(Self.quotaKey).remaining(limit: Self.freeImportsPerDay)
    }

    /// Uses one import; false when the free plan's daily limit is reached.
    func consumeImport() -> Bool {
        guard !isUnlocked else { return true }
        var quota = ImportQuota.load(Self.quotaKey)
        guard quota.consume(limit: Self.freeImportsPerDay) else { return false }
        quota.save(Self.quotaKey)
        objectWillChange.send()
        return true
    }

    static let limitMessage = "Free plan: \(freeImportsPerDay) imports a day. Upgrade to Pro for unlimited, or tap Try again tomorrow."
}

/// Pure counter that resets each calendar day (unit-tested).
struct ImportQuota: Codable, Equatable {
    var day: String = ""
    var used = 0

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    func remaining(limit: Int, now: Date = .now) -> Int {
        day == Self.dayKey(now) ? max(0, limit - used) : limit
    }

    mutating func consume(limit: Int, now: Date = .now) -> Bool {
        let today = Self.dayKey(now)
        if day != today { day = today; used = 0 }
        guard used < limit else { return false }
        used += 1
        return true
    }

    static func load(_ key: String) -> ImportQuota {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(ImportQuota.self, from: $0) } ?? ImportQuota()
    }

    func save(_ key: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: key) }
    }
}
