import SwiftUI
import CoreData

/// Shared packing & pre-trip checklist, grouped by category.
struct PackingListView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)])
    private var allTrips: FetchedResults<Trip>

    @State private var newTitle = ""
    @State private var newCategory: PackingCategory = .essentials
    @State private var refreshTick = 0
    @FocusState private var addFocused: Bool

    private var items: [PackingItem] { trip.sortedPackingItems }

    var body: some View {
        let _ = refreshTick
        NavigationStack {
            List {
                Section {
                    progressHeader
                }

                ForEach(PackingCategory.allCases) { category in
                    let group = items.filter { $0.category == category }
                    if !group.isEmpty {
                        Section {
                            ForEach(group) { item in
                                PackingRow(item: item) { save() }
                            }
                            .onDelete { offsets in
                                offsets.map { group[$0] }.forEach(context.delete)
                                save()
                            }
                        } header: {
                            Label(category.title, systemImage: category.systemImage)
                        }
                    }
                }

                Section("Add") {
                    HStack {
                        TextField("e.g. Reef-safe sunscreen", text: $newTitle)
                            .focused($addFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Menu {
                            Picker("Category", selection: $newCategory) {
                                ForEach(PackingCategory.allCases) { category in
                                    Label(category.title, systemImage: category.systemImage).tag(category)
                                }
                            }
                        } label: {
                            Image(systemName: newCategory.systemImage)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Category: \(newCategory.title)")
                    }
                    let missing = missingSuggestions.count
                    if missing > 0 {
                        Button {
                            addSuggestions()
                        } label: {
                            Label(items.isEmpty ? "Add Thailand essentials (\(missing) items)" : "Add the \(missing) missing Thailand essentials",
                                  systemImage: "sparkles")
                        }
                    }
                    ForEach(otherTripsWithPacking, id: \.objectID) { other in
                        let count = copyable(from: other).count
                        if count > 0 {
                            Button {
                                copy(from: other)
                            } label: {
                                Label("Copy \(count) item\(count == 1 ? "" : "s") from \"\(other.name ?? "another trip")\"",
                                      systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Packing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                refreshTick &+= 1
            }
        }
    }

    private var progressHeader: some View {
        let done = items.filter(\.isDone).count
        let progress = items.isEmpty ? 0 : Double(done) / Double(items.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(items.isEmpty ? "Nothing on the list yet" : "\(done) of \(items.count) packed")
                    .font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(progress >= 1 ? .green : Theme.mango)
            }
            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : Theme.mango)
            Text("Shared with everyone on this trip.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        insert(title, category: newCategory)
        newTitle = ""
        addFocused = true
        save()
    }

    private func insert(_ title: String, category: PackingCategory) {
        let item = PackingItem(context: context)
        item.placeInSameStore(as: trip)
        item.uuid = UUID()
        item.title = title
        item.category = category
        item.sortIndex = (items.map(\.sortIndex).max() ?? -1) + 1
        item.addedBy = AppSettings.displayName
        item.trip = trip
    }

    private var existingTitles: Set<String> { Set(items.compactMap { $0.title?.lowercased() }) }

    private var missingSuggestions: [(String, PackingCategory)] {
        let existing = existingTitles
        return Self.suggestions.filter { !existing.contains($0.0.lowercased()) }
    }

    private func addSuggestions() {
        for (title, category) in missingSuggestions {
            insert(title, category: category)
        }
        save()
    }

    private var otherTripsWithPacking: [Trip] {
        allTrips.filter { $0.objectID != trip.objectID && !$0.sortedPackingItems.isEmpty }
    }

    /// Items on another trip's list that this trip doesn't have yet.
    private func copyable(from other: Trip) -> [PackingItem] {
        let existing = existingTitles
        return other.sortedPackingItems.filter { !existing.contains(($0.title ?? "").lowercased()) }
    }

    /// Copies another trip's packing items (unchecked) into this trip.
    private func copy(from other: Trip) {
        for source in copyable(from: other) {
            guard let title = source.title else { continue }
            insert(title, category: source.category)
        }
        save()
    }

    private func save() {
        ItineraryStore(context: context).save()
    }

    static let suggestions: [(String, PackingCategory)] = [
        ("Passport (valid 6+ months)", .documents),
        ("Printed/hotel bookings & return flight", .documents),
        ("Travel insurance policy", .documents),
        ("Check visa / TDAC arrival card rules", .todo),
        ("Tell your bank you're traveling", .todo),
        ("Download offline Apple/Google maps of each city", .todo),
        ("Download Thai language pack (Translate tab)", .todo),
        ("eSIM or local SIM plan", .tech),
        ("Universal plug adapter (types A/B/C/O)", .tech),
        ("Power bank", .tech),
        ("Comfortable walking shoes", .clothing),
        ("Light clothes covering shoulders & knees (temples)", .clothing),
        ("Rain jacket / poncho", .clothing),
        ("Sunscreen", .health),
        ("Mosquito repellent (DEET)", .health),
        ("Rehydration salts & basic meds", .health),
        ("Reusable water bottle", .essentials),
        ("Small daypack", .essentials),
        ("Some cash in baht for arrival", .essentials)
    ]
}

private struct PackingRow: View {
    @ObservedObject var item: PackingItem
    let onChange: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy) { item.isDone.toggle() }
            onChange()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isDone ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "")
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                    if let addedBy = item.addedBy, !addedBy.isEmpty, addedBy != AppSettings.displayName {
                        Text("Added by \(addedBy)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: item.isDone) { _, isDone in isDone }
        .accessibilityValue(item.isDone ? "Packed" : "Not packed")
    }
}
