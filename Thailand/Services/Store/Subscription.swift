import Foundation
import StoreKit

/// Free plan: a few imports a day. WanderHub Pro (monthly / yearly, StoreKit 2): unlimited.
/// Everything is unlocked in Xcode and TestFlight builds so testers never hit the paywall.
///
/// App Store Connect setup: create an auto-renewable subscription group "WanderHub Pro" with
/// products `com.kbreed.thailandtrip.pro.monthly` and `com.kbreed.thailandtrip.pro.yearly`.
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
        if let app = try? await AppTransaction.shared, case .verified(let info) = app {
            // TestFlight and Xcode builds run in the sandbox / xcode environments.
            if info.environment == .sandbox || info.environment == .xcode { isTestBuild = true }
        }
        await refreshEntitlements()
        products = ((try? await Product.products(for: Self.productIDs)) ?? []).sorted { $0.price < $1.price }
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
