import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Subscription.shared

    private let perks: [(String, String)] = [
        ("infinity", "Unlimited imports from TikTok, Instagram, YouTube, Maps, web and screenshots"),
        ("wand.and.sparkles", "Auto-plan every day of your trip"),
        ("dice", "Unlimited sidequests"),
        ("heart", "Support an indie travel app"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "airplane.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.mango)
                    Text("WanderHub Pro").font(.largeTitle.weight(.bold))
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(perks, id: \.1) { icon, text in
                            Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Theme.lagoon) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    if store.isTestBuild {
                        Label("Everything is unlocked in this test build.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else if store.isPro {
                        Label("You're Pro. Thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else if store.products.isEmpty {
                        ProgressView()
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                Task { await store.purchase(product) }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(product.displayName).font(.headline)
                                    Text("\(product.displayPrice) / \(product.subscription?.subscriptionPeriod.unit == .year ? "year" : "month")").font(.subheadline)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.mango)
                            .disabled(store.purchasing)
                        }
                    }
                    if let message = store.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    Text("Free plan: \(Subscription.freeImportsPerDay) imports a day. Subscriptions renew automatically until cancelled in Settings → Apple Account → Subscriptions.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 20) {
                        Button("Restore purchases") { Task { await store.restore() } }
                        Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.footnote)
                }
                .padding()
            }
            .background(Theme.background)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await store.start() }
        }
    }
}
