import StoreKit
import SwiftUI

/// WanderHub Pro: annual or monthly (with a 3-day free trial), with the disclosures Apple requires
/// (price, length, auto-renewal, how to cancel, Terms and Privacy links, Restore).
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Subscription.shared
    @State private var selectedID = Subscription.productIDs[1]
    @State private var redeeming = false

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://kbreed1280.github.io/Thailand/privacy.html")!

    private let perks: [(String, String)] = [
        ("infinity", "Unlimited imports from TikTok, Instagram, YouTube, Maps, web and screenshots"),
        ("sparkle.magnifyingglass", "Research missing places from any post"),
        ("wand.and.sparkles", "Auto-plan every day of your trip"),
        ("dice", "Unlimited sidequests"),
    ]

    private var selected: Product? { store.products.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse.circle.fill")
                            .font(.system(size: 64)).foregroundStyle(PlotStyle.ink)
                        Text("WanderHub Pro").font(.largeTitle.weight(.bold))
                        Text("Save every spot. Plan every day.").foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(perks, id: \.1) { icon, text in
                            Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Theme.lagoon) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if store.isTestBuild {
                        Label("Everything is unlocked in Xcode builds.", systemImage: "hammer.fill").foregroundStyle(.secondary)
                    } else if store.isPro {
                        Label("You're Pro. Thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else if store.products.isEmpty {
                        ProgressView().padding()
                    } else {
                        plans
                        purchaseButton
                    }

                    if let message = store.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    disclosure
                }
                .padding()
            }
            .background(PlotStyle.paper)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await store.start() }
            // Apple's offer-code sheet (codes from App Store Connect → Subscriptions → Offer Codes).
            .offerCodeRedemption(isPresented: $redeeming) { _ in
                Task { await store.refreshEntitlements() }
            }
        }
        .fontDesign(.rounded)
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if let yearly = store.yearly {
                planCard(yearly, title: "Annual", price: "\(yearly.displayPrice) / year",
                         detail: perMonth(yearly).map { "Just \($0)/month" },
                         badge: store.yearlySavingsPercent.map { "SAVE \($0)%" })
            }
            if let monthly = store.monthly {
                planCard(monthly, title: "Monthly", price: "\(monthly.displayPrice) / month",
                         detail: store.trialText(for: monthly).map { "\($0), then \(monthly.displayPrice)/month" },
                         badge: store.trialText(for: monthly) != nil ? "FREE TRIAL" : nil)
            }
        }
    }

    private func planCard(_ product: Product, title: String, price: String, detail: String?, badge: String?) -> some View {
        let on = selectedID == product.id
        return Button { selectedID = product.id } label: {
            HStack(spacing: 14) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(on ? PlotStyle.ink : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge).font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.mango, in: Capsule())
                        }
                    }
                    Text(price).font(.subheadline)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding()
            .background(PlotStyle.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(on ? PlotStyle.ink : PlotStyle.line, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var purchaseButton: some View {
        Button {
            if let selected { Task { await store.purchase(selected) } }
        } label: {
            Group {
                if store.purchasing { ProgressView().tint(.white) }
                else if let selected, store.trialText(for: selected) != nil { Text("Start free trial") }
                else { Text("Continue") }
            }
            .font(.headline)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(PlotStyle.ink, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(selected == nil || store.purchasing)
    }

    private var disclosure: some View {
        VStack(spacing: 10) {
            Text(disclosureText)
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Button("Restore purchases") { Task { await store.restore() } }
                Button("Redeem code") { redeeming = true }
                Link("Terms of Use", destination: Self.termsURL)
                Link("Privacy Policy", destination: Self.privacyURL)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var disclosureText: String {
        var text = "Free plan: \(Subscription.freeImportsPerDay) imports a day. "
        if let selected, let trial = store.trialText(for: selected) {
            text += "\(trial.capitalized(with: nil)), then \(selected.displayPrice) per \(selected.id == Subscription.productIDs[1] ? "year" : "month"). "
        }
        text += "Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple Account → Subscriptions."
        return text
    }

    private func perMonth(_ product: Product) -> String? {
        let monthly = product.price / 12
        return monthly.formatted(product.priceFormatStyle)
    }
}
