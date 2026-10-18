import SwiftUI
import CoreData

/// Trip budget card on the Overview: spent vs. budget, with a bar. Tap to open the full budget.
struct BudgetCard: View {
    @ObservedObject var trip: Trip
    let onOpen: () -> Void

    var body: some View {
        let summary = trip.budgetSummary
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Budget", systemImage: "chart.pie.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                if summary.budget > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text(CurrencyMath.format(summary.spent, .local))
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("of \(CurrencyMath.format(summary.budget, .local))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(summary.remaining >= 0
                             ? "\(CurrencyMath.format(summary.remaining, .local)) left"
                             : "\(CurrencyMath.format(-summary.remaining, .local)) over")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(summary.remaining >= 0 ? Theme.lagoon : Theme.coral)
                    }
                    BudgetBar(fraction: summary.fraction)
                } else {
                    Text(summary.spent > 0
                         ? "Spent \(CurrencyMath.format(summary.spent, .local)) so far. Set a budget to track what's left."
                         : "Set a budget for the trip and track spending against it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the trip budget")
    }
}

struct BudgetBar: View {
    let fraction: Double
    var tint: Color { fraction > 1 ? Theme.coral : fraction > 0.85 ? Theme.mango : Theme.lagoon }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.insetBackground)
                Capsule().fill(tint).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent of budget used")
    }
}

/// Set the trip budget (overall and per category) and see spending against it.
struct BudgetView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip

    @State private var total: Double?
    @State private var categories: [ExpenseCategory: Double] = [:]
    @State private var showingExpenses = false

    private var canEdit: Bool { PersistenceController.shared.canEdit(trip) }

    var body: some View {
        let summary = BudgetMath.summary(
            total: total ?? 0,
            perCategory: categories,
            expenses: trip.sortedExpenses.map { (category: $0.category, amount: $0.amountTHB) },
            plannedCosts: trip.allItems.filter { $0.status != .done && $0.costTHB > 0 }.map(\.costTHB)
        )
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(CurrencyMath.format(summary.spent, .local))
                                .font(.largeTitle.bold().monospacedDigit())
                            if summary.budget > 0 {
                                Text("of \(CurrencyMath.format(summary.budget, .local))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if summary.budget > 0 {
                            BudgetBar(fraction: summary.fraction)
                            Text(summary.remaining >= 0
                                 ? "\(CurrencyMath.format(summary.remaining, .local)) left to spend"
                                 : "\(CurrencyMath.format(-summary.remaining, .local)) over budget")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(summary.remaining >= 0 ? Theme.lagoon : Theme.coral)
                        }
                        if summary.planned > 0 {
                            Text("Plus \(CurrencyMath.format(summary.planned, .local)) in planned costs on your itinerary (projected \(CurrencyMath.format(summary.projected, .local))).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("Log an Expense", systemImage: "plus.circle") { showingExpenses = true }
                }

                Section {
                    LabeledContent("Whole trip") {
                        TextField("No budget", value: $total, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!canEdit)
                    }
                } header: {
                    Text("Total budget (\(Currency.local.code))")
                } footer: {
                    Text("Leave it empty to use the sum of the category budgets below.")
                }

                Section("By category") {
                    ForEach(ExpenseCategory.allCases) { category in
                        let line = summary.lines.first { $0.category == category }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(category.title, systemImage: category.systemImage)
                                Spacer()
                                TextField("—", value: Binding(
                                    get: { categories[category] },
                                    set: { categories[category] = ($0 ?? 0) > 0 ? $0 : nil }
                                ), format: .number.precision(.fractionLength(0...2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                                    .disabled(!canEdit)
                            }
                            if let line, line.spent > 0 || line.budget > 0 {
                                if line.budget > 0 { BudgetBar(fraction: line.fraction) }
                                Text(line.budget > 0
                                     ? "Spent \(CurrencyMath.format(line.spent, .local)) · \(line.remaining >= 0 ? "\(CurrencyMath.format(line.remaining, .local)) left" : "\(CurrencyMath.format(-line.remaining, .local)) over")"
                                     : "Spent \(CurrencyMath.format(line.spent, .local))")
                                    .font(.caption)
                                    .foregroundStyle(line.remaining < 0 && line.budget > 0 ? Theme.coral : .secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .onAppear {
                total = trip.budgetTotal > 0 ? trip.budgetTotal : nil
                categories = trip.categoryBudgets
            }
            .sheet(isPresented: $showingExpenses) {
                NavigationStack {
                    ExpensesView(trip: trip)
                        .navigationTitle("Expenses")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") { showingExpenses = false } }
                        }
                }
            }
        }
    }

    private func save() {
        guard canEdit else { return }
        trip.budgetTotal = max(total ?? 0, 0)
        trip.categoryBudgets = categories
        ItineraryStore(context: context).save()
    }
}
