import SwiftUI
import CoreData

/// Shared expenses for a trip: totals, balances, settle-up suggestions and the list.
struct ExpensesView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var trip: Trip
    @StateObject private var rates = ExchangeRateStore.shared

    @State private var editing: ExpenseEditTarget?
    @State private var refreshTick = 0

    private var expenses: [Expense] { trip.sortedExpenses }

    /// Everyone who has paid for something, plus you.
    private var participants: [String] {
        var names = [AppSettings.displayName]
        for name in expenses.compactMap(\.paidBy) where !name.isEmpty && !names.contains(name) {
            names.append(name)
        }
        return names
    }

    private var balances: [String: Double] {
        CurrencyMath.balances(
            for: expenses.map {
                CurrencyMath.Share(amount: $0.amountTHB, paidBy: $0.paidBy ?? "", split: $0.split, payerShare: $0.payerShare)
            },
            participants: participants
        )
    }

    var body: some View {
        let _ = refreshTick
        List {
            Section {
                summary
            }

            if participants.count > 1 {
                Section("Settle Up") {
                    let transfers = CurrencyMath.settlements(for: balances)
                    if transfers.isEmpty {
                        Label("All square — nobody owes anything.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(Array(transfers.enumerated()), id: \.offset) { _, transfer in
                        HStack {
                            Text("\(transfer.from) owes \(transfer.to)")
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(CurrencyMath.format(transfer.amount, .thb)).bold().monospacedDigit()
                                Text(usd(transfer.amount)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section("Expenses") {
                if expenses.isEmpty {
                    Text("Nothing logged yet. Tap + after you pay for a meal, ticket or taxi.")
                        .foregroundStyle(.secondary)
                }
                ForEach(expenses) { expense in
                    Button {
                        editing = ExpenseEditTarget(expense: expense)
                    } label: {
                        ExpenseRow(expense: expense, usd: usd(expense.amountTHB))
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    offsets.map { expenses[$0] }.forEach(context.delete)
                    ItineraryStore(context: context).save()
                }
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = ExpenseEditTarget(expense: nil)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Add expense")
            }
        }
        .sheet(item: $editing) { target in
            ExpenseEditorView(expense: target.expense, trip: trip, knownNames: participants)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
            refreshTick &+= 1
        }
    }

    private var summary: some View {
        let total = expenses.reduce(0) { $0 + $1.amountTHB }
        let byCategory = Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amountTHB } }
            .sorted { $0.value > $1.value }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total spent").font(.caption).foregroundStyle(.secondary)
                    Text(CurrencyMath.format(total, .thb)).font(.largeTitle.bold().monospacedDigit())
                }
                Spacer()
                Text(usd(total))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.lagoon)
            }

            if !byCategory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(byCategory, id: \.key) { entry in
                            StatPill(systemImage: entry.key.systemImage, text: CurrencyMath.format(entry.value, .thb), tint: Theme.mango)
                        }
                    }
                }
            }

            if participants.count > 1 {
                ForEach(participants, id: \.self) { name in
                    let value = balances[name] ?? 0
                    HStack {
                        Text(name)
                        Spacer()
                        Text(value >= 0 ? "gets back \(CurrencyMath.format(value, .thb))" : "owes \(CurrencyMath.format(-value, .thb))")
                            .foregroundStyle(value >= 0 ? .green : .orange)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            } else {
                Text("When your travel partner pays for something, log it with their name and the app works out who owes whom.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func usd(_ thb: Double) -> String {
        CurrencyMath.format(CurrencyMath.convert(thb, from: .thb, thbPerUSD: rates.thbPerUSD), .usd)
    }
}

struct ExpenseEditTarget: Identifiable {
    let id = UUID()
    let expense: Expense?
}

private struct ExpenseRow: View {
    @ObservedObject var expense: Expense
    let usd: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.systemImage)
                .font(.headline)
                .foregroundStyle(Theme.mango)
                .frame(width: 38, height: 38)
                .background(Theme.mango.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title ?? "Expense").font(.body.weight(.medium))
                Text("\(expense.paidBy ?? "") paid · \(expense.split.title)\(expense.date.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyMath.format(expense.amountTHB, .thb)).font(.body.weight(.semibold).monospacedDigit())
                Text(usd).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Add or edit an expense.
struct ExpenseEditorView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rates = ExchangeRateStore.shared

    let expense: Expense?
    let trip: Trip
    let knownNames: [String]

    @State private var title = ""
    @State private var amountText = ""
    @State private var paidBy = ""
    @State private var split: ExpenseSplit = .equal
    @State private var payerShare = 0.5
    @State private var category: ExpenseCategory = .food
    @State private var date = Date.now
    @State private var didLoad = false

    private var amount: Double? { CurrencyMath.parseAmount(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What for? (e.g. Dinner at night market)", text: $title)
                    HStack {
                        Text("฿").font(.title2.bold()).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit())
                        if let amount {
                            Text("≈ " + CurrencyMath.format(CurrencyMath.convert(amount, from: .thb, thbPerUSD: rates.thbPerUSD), .usd))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Who paid?") {
                    if !knownNames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(knownNames, id: \.self) { name in
                                    Button(name) { paidBy = name }
                                        .buttonStyle(.bordered)
                                        .tint(paidBy == name ? Theme.mango : .gray)
                                }
                            }
                        }
                    }
                    TextField("Name", text: $paidBy)
                        .textContentType(.givenName)
                }

                Section {
                    Picker("Split", selection: $split) {
                        ForEach(ExpenseSplit.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    if split == .custom {
                        VStack(alignment: .leading) {
                            Text("\(paidBy.isEmpty ? "Payer" : paidBy) covers \(Int(payerShare * 100))%")
                            Slider(value: $payerShare, in: 0...1, step: 0.05)
                                .tint(Theme.mango)
                        }
                    }
                } header: {
                    Text("Split")
                } footer: {
                    Text(splitExplanation)
                }
            }
            .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .bold()
                        .disabled((amount ?? 0) <= 0 || paidBy.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var splitExplanation: String {
        switch split {
        case .equal: "Shared equally by everyone on the trip."
        case .payerOnly: "Only the payer's — nobody owes anything."
        case .custom: "The payer covers their share; everyone else splits the rest."
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let expense else {
            paidBy = AppSettings.displayName
            return
        }
        title = expense.title ?? ""
        amountText = String(CurrencyMath.format(expense.amountTHB, .thb).dropFirst())
        paidBy = expense.paidBy ?? ""
        split = expense.split
        payerShare = expense.payerShare
        category = expense.category
        date = expense.date ?? .now
    }

    private func save() {
        let target = expense ?? {
            let new = Expense(context: context)
            new.placeInSameStore(as: trip)
            new.uuid = UUID()
            new.addedBy = AppSettings.displayName
            new.trip = trip
            return new
        }()
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        target.title = trimmedTitle.isEmpty ? category.title : trimmedTitle
        target.amountTHB = amount ?? 0
        target.paidBy = paidBy.trimmingCharacters(in: .whitespaces)
        target.split = split
        target.payerShare = payerShare
        target.category = category
        target.date = date
        ItineraryStore(context: context).save()
        dismiss()
    }
}
