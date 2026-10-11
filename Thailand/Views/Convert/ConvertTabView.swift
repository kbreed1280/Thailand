import SwiftUI

/// Converter between the trip's local money and your home money, quick amounts, rate details,
/// tip calculator and the trip's spending.
struct ConvertTabView: View {
    /// Shown as a sheet from the Trip screen: adds a Done button.
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rates = ExchangeRateStore.shared
    @ObservedObject private var network = NetworkMonitor.shared

    private enum Field { case top, bottom }

    @State private var topCurrency: Currency = .local
    @State private var topText = ""
    @State private var bottomText = ""
    @FocusState private var focus: Field?
    @State private var showingManualRate = false
    @State private var manualRateText = ""
    @State private var showingExchange = false

    private var bottomCurrency: Currency { topCurrency.other }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    converterCard
                    quickAmounts
                    rateCard
                    Button { showingExchange = true } label: {
                        Label("Find money exchange near me", systemImage: "mappin.and.ellipse")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    TipCard(localPerHome: rates.localPerHome)
                    CurrentTripReader { trip in
                        if let trip {
                            TripSpendingCard(trip: trip, localPerHome: rates.localPerHome)
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .skyBackground()
            .navigationTitle("Convert")
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .task { await rates.refreshIfNeeded() }
            .sheet(isPresented: $showingExchange) { MoneyExchangeView() }
            .refreshable { await rates.refresh() }
            .onChange(of: topText) { _, _ in if focus == .top { recalculate(from: .top) } }
            .onChange(of: bottomText) { _, _ in if focus == .bottom { recalculate(from: .bottom) } }
            .onChange(of: rates.rate) { _, _ in recalculate(from: .top) }
            .onChange(of: rates.localCode) { _, _ in recalculate(from: .top) }
            .alert("Set Exchange Rate", isPresented: $showingManualRate) {
                TextField("\(rates.localCode) per 1 \(rates.homeCode)", text: $manualRateText)
                    .keyboardType(.decimalPad)
                Button("Save") {
                    if let value = CurrencyMath.parseAmount(manualRateText), value > 0 {
                        rates.setManualRate(value)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use the rate from your bank, a money changer board, or an ATM receipt.")
            }
        }
    }

    // MARK: Converter

    private var converterCard: some View {
        VStack(spacing: 0) {
            CurrencyField(currency: topCurrency, text: $topText, isFocused: focus == .top)
                .focused($focus, equals: .top)
            ZStack {
                Divider()
                Button(action: swap) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Theme.sunsetGradient, in: Circle())
                        .shadow(color: Theme.mango.opacity(0.4), radius: 6, y: 3)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Swap currencies")
                .sensoryFeedback(.selection, trigger: topCurrency)
            }
            .frame(height: 48)
            CurrencyField(currency: bottomCurrency, text: $bottomText, isFocused: focus == .bottom)
                .focused($focus, equals: .bottom)
        }
        .card(padding: 18)
    }

    private var quickAmounts: some View {
        HStack(spacing: 8) {
            ForEach(quickAmountValues, id: \.self) { amount in
                Button {
                    setAmount(Double(amount), in: .local)
                } label: {
                    Text("\(Currency.local.symbol)\(amount.formatted())")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.cardBackground, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.mango.opacity(0.35)))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(amount) \(Currency.local.name)")
            }
        }
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("1 \(rates.homeCode) = \(CurrencyMath.format(rates.localPerHome, .local).dropFirst(Currency.local.symbol.count)) \(rates.localCode)")
                    .font(.title3.bold().monospacedDigit())
                Spacer()
                if !network.isOnline { OfflineBadge() }
            }
            Text("1 \(rates.localCode) = \(Currency.home.symbol)\(String(format: rates.localPerHome > 100 ? "%.5f" : "%.4f", 1 / rates.localPerHome))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            if let rate = rates.rate {
                Label(
                    "\(rate.isManual ? "Set by you" : "Rate as of") \(rate.asOf.formatted(date: .abbreviated, time: .shortened)) · \(rate.source)",
                    systemImage: rate.isManual ? "hand.raised.fill" : "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let error = rates.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await rates.refresh() }
                } label: {
                    if rates.isRefreshing {
                        ProgressView()
                    } else {
                        Label("Update", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!network.isOnline || rates.isRefreshing || rates.rate?.isManual == true)

                Button {
                    manualRateText = String(format: "%.2f", rates.localPerHome)
                    showingManualRate = true
                } label: {
                    Label("Set Rate", systemImage: "pencil")
                }

                if rates.rate?.isManual == true {
                    Button {
                        Task { await rates.clearManualRate() }
                    } label: {
                        Label("Use Live", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(!network.isOnline)
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.lagoon)
            .font(.subheadline.weight(.semibold))
        }
        .card()
    }

    /// Round local amounts worth roughly 1, 3, 10, 30 and 100 in home money (฿50…, ¥200…, €1…).
    private var quickAmountValues: [Int] {
        let rate = rates.localPerHome
        let targets: [Double] = [1, 3, 10, 30, 100]
        return Array(Set(targets.map { nice($0 * rate) })).filter { $0 > 0 }.sorted().prefix(5).map { $0 }
    }

    private func nice(_ value: Double) -> Int {
        guard value >= 1 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        let steps: [Double] = [1, 2, 5, 10]
        let step = steps.min { abs($0 * magnitude - value) < abs($1 * magnitude - value) } ?? 1
        return Int(step * magnitude)
    }

    // MARK: Logic

    private func swap() {
        withAnimation(.snappy) {
            topCurrency = topCurrency.other
            let oldTop = topText
            topText = bottomText
            bottomText = oldTop
        }
    }

    private func setAmount(_ amount: Double, in currency: Currency) {
        focus = nil
        if currency == topCurrency {
            topText = plain(amount, currency)
            recalculate(from: .top)
        } else {
            bottomText = plain(amount, currency)
            recalculate(from: .bottom)
        }
    }

    private func recalculate(from field: Field) {
        let rate = rates.localPerHome
        switch field {
        case .top:
            guard let value = CurrencyMath.parseAmount(topText) else {
                bottomText = ""
                return
            }
            bottomText = plain(CurrencyMath.convert(value, from: topCurrency, localPerHome: rate), bottomCurrency)
        case .bottom:
            guard let value = CurrencyMath.parseAmount(bottomText) else {
                topText = ""
                return
            }
            topText = plain(CurrencyMath.convert(value, from: bottomCurrency, localPerHome: rate), topCurrency)
        }
    }

    /// Formatted number without the currency symbol (the field shows the symbol separately).
    private func plain(_ value: Double, _ currency: Currency) -> String {
        String(CurrencyMath.format(value, currency).dropFirst(currency.symbol.count))
    }
}

private struct CurrencyField: View {
    let currency: Currency
    @Binding var text: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(currency.flag)
                .font(.largeTitle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(currency.code)
                    .font(.headline)
                Text(currency.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(currency.symbol)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            TextField("0", text: $text)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Amount in \(currency.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                .fill(isFocused ? Theme.mango.opacity(0.08) : .clear)
        )
    }
}

/// Bill + tip % → tip and total in both currencies.
private struct TipCard: View {
    let localPerHome: Double

    @State private var billText = ""
    @State private var tipPercent = 10.0

    private var bill: Double { CurrencyMath.parseAmount(billText) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tip", systemImage: "hand.thumbsup.fill")
                .font(.headline)

            HStack {
                Text("Bill \(Currency.local.symbol)")
                    .foregroundStyle(.secondary)
                TextField("0", text: $billText)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            .padding(12)
            .background(Theme.insetBackground, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))

            Picker("Tip", selection: $tipPercent) {
                Text("No tip").tag(0.0)
                Text("5%").tag(5.0)
                Text("10%").tag(10.0)
                Text("15%").tag(15.0)
            }
            .pickerStyle(.segmented)

            if bill > 0 {
                let tip = CurrencyMath.tip(on: bill, percent: tipPercent)
                let total = bill + tip
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total with tip").font(.caption).foregroundStyle(.secondary)
                        Text(CurrencyMath.format(total, .local))
                            .font(.title.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CurrencyMath.format(CurrencyMath.convert(total, from: .local, localPerHome: localPerHome), .home))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.lagoon)
                        Text("Tip \(CurrencyMath.format(tip, .local))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(CurrentDestination.isThailand
                 ? "Tipping isn't required in Thailand. Rounding up, or about 10% at sit-down restaurants without a service charge, is appreciated."
                 : "Tipping customs vary by country. Check whether a service charge is already on the bill.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

/// Planned costs (from itinerary items) and logged expenses, in both currencies.
private struct TripSpendingCard: View {
    @ObservedObject var trip: Trip
    let localPerHome: Double

    var body: some View {
        let planned = trip.allItems.reduce(0) { $0 + $1.costTHB }
        let spent = trip.sortedExpenses.reduce(0) { $0 + $1.amountTHB }

        NavigationLink {
            ExpensesView(trip: trip)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Trip Spending", systemImage: "chart.pie.fill")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .top) {
                    amountBlock(title: "Spent so far", thb: spent, tint: Theme.mango)
                    Spacer()
                    amountBlock(title: "Planned in itinerary", thb: planned, tint: Theme.lagoon)
                }
                Text("Log who paid for what and see who owes whom →")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .card()
        }
        .buttonStyle(.plain)
    }

    private func amountBlock(title: String, thb: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(CurrencyMath.format(thb, .local))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(tint)
            Text(CurrencyMath.format(CurrencyMath.convert(thb, from: .local, localPerHome: localPerHome), .home))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ConvertTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
