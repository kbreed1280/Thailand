import SwiftUI
import CoreData

/// The itinerary: trip header, wish list and one section per day.
/// Drag any row onto another row (or a day header) to move it there.
struct TripItineraryView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var trip: Trip
    let allTrips: [Trip]
    @Binding var selectedTripID: String

    @State private var refreshTick = 0
    @State private var wishListExpanded = true
    @State private var editingNewItemFor: NewItemTarget?
    @State private var showingStarterIdeas = false
    @State private var showingPacking = false
    @State private var showingEditTrip = false
    @State private var showingNewTrip = false
    @State private var showingProfile = false
    @State private var confirmingDelete = false
    @State private var mapDay: Day?

    private var store: ItineraryStore { ItineraryStore(context: context) }

    var body: some View {
        // Re-read relationships whenever anything in the store changes (local edits or sync).
        let _ = refreshTick
        List {
            Section {
                TripHeaderCard(trip: trip) {
                    showingPacking = true
                } onIdeas: {
                    showingStarterIdeas = true
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            wishListSection

            ForEach(trip.sortedDays) { day in
                daySection(day)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(trip.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu { tripMenu }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingNewItemFor = NewItemTarget(day: trip.today)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Add to itinerary")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
            refreshTick &+= 1
        }
        .sheet(item: $editingNewItemFor) { target in
            ItemEditorView(item: nil, trip: trip, initialDay: target.day)
        }
        .sheet(isPresented: $showingStarterIdeas) {
            StarterIdeasView(trip: trip)
        }
        .sheet(isPresented: $showingPacking) {
            PackingListView(trip: trip)
        }
        .sheet(isPresented: $showingEditTrip) {
            TripFormView(trip: trip)
        }
        .sheet(isPresented: $showingNewTrip) {
            TripFormView(trip: nil) { newTrip in
                selectedTripID = newTrip.uuid?.uuidString ?? ""
            }
        }
        .sheet(isPresented: $showingProfile) {
            ProfileSheet()
        }
        .sheet(item: $mapDay) { day in
            DayMapView(day: day)
        }
        .confirmationDialog("Delete \(trip.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                store.delete(trip)
                store.save()
                selectedTripID = ""
            }
        } message: {
            Text("Every day, place, photo, expense and packing item in this trip is deleted.")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var wishListSection: some View {
        Section {
            if wishListExpanded {
                let items = trip.sortedWishItems
                if items.isEmpty {
                    DropPlaceholder(text: "Places you want to visit but haven't scheduled. Add from Starter Ideas, Explore or Nearby.") { ids in
                        drop(ids, onto: nil, before: nil)
                    }
                }
                ForEach(items) { item in
                    row(for: item, in: nil)
                }
            }
        } header: {
            HStack {
                Button {
                    withAnimation { wishListExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.mango)
                        Text("Wish List")
                        Text("\(trip.sortedWishItems.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: wishListExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wish list, \(trip.sortedWishItems.count) places, \(wishListExpanded ? "expanded" : "collapsed")")
                Spacer()
                Button {
                    editingNewItemFor = NewItemTarget(day: nil)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 32)
                }
                .accessibilityLabel("Add to wish list")
            }
            .font(.headline)
            .textCase(nil)
            .foregroundStyle(.primary)
            .dropDestination(for: String.self) { ids, _ in
                drop(ids, onto: nil, before: nil)
            }
        }
    }

    private func daySection(_ day: Day) -> some View {
        Section {
            let items = day.sortedItems
            if items.isEmpty {
                DropPlaceholder(text: "Nothing planned yet. Tap + or drag a place here.") { ids in
                    drop(ids, onto: day, before: nil)
                }
            }
            ForEach(items) { item in
                row(for: item, in: day)
            }
        } header: {
            DayHeader(day: day) {
                mapDay = day
            } onAdd: {
                editingNewItemFor = NewItemTarget(day: day)
            }
            .dropDestination(for: String.self) { ids, _ in
                drop(ids, onto: day, before: nil)
            }
        }
    }

    private func row(for item: Item, in day: Day?) -> some View {
        NavigationLink(value: item) {
            ItemRow(item: item)
        }
        .draggable(item.uuid?.uuidString ?? "") {
            ItemRow(item: item)
                .padding(10)
                .frame(width: 300)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
        }
        .dropDestination(for: String.self) { ids, _ in
            drop(ids, onto: day, before: item)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation {
                    store.delete(item)
                    store.save()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                store.setStatus(item.status == .done ? .wantToGo : .done, for: item)
                store.save()
            } label: {
                Label(item.status == .done ? "Undo" : "Done", systemImage: item.status == .done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(item.status == .done ? .gray : .green)
        }
        .contextMenu {
            Menu {
                Button("Wish List", systemImage: "star") { move(item, to: nil) }
                ForEach(trip.sortedDays) { target in
                    Button(target.heading) { move(item, to: target) }
                }
            } label: {
                Label("Move to…", systemImage: "arrow.right.circle")
            }
            Picker("Status", selection: Binding(
                get: { item.status },
                set: { store.setStatus($0, for: item); store.save() }
            )) {
                ForEach(ItemStatus.allCases) { status in
                    Label(status.title, systemImage: status.systemImage).tag(status)
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.delete(item)
                store.save()
            }
        }
    }

    // MARK: Menus & actions

    @ViewBuilder
    private var tripMenu: some View {
        if allTrips.count > 1 {
            Section("Switch Trip") {
                ForEach(allTrips) { other in
                    Button {
                        selectedTripID = other.uuid?.uuidString ?? ""
                    } label: {
                        if other == trip {
                            Label(other.displayName, systemImage: "checkmark")
                        } else {
                            Text(other.displayName)
                        }
                    }
                }
            }
        }
        Section {
            Button("Edit Trip", systemImage: "pencil") { showingEditTrip = true }
            Button("Packing List", systemImage: "suitcase.rolling") { showingPacking = true }
            Button("Starter Ideas", systemImage: "lightbulb") { showingStarterIdeas = true }
            Button("Your Name", systemImage: "person.crop.circle") { showingProfile = true }
        }
        Section {
            Button("New Trip", systemImage: "plus") { showingNewTrip = true }
            Button("Delete Trip", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        }
    }

    private func move(_ item: Item, to day: Day?) {
        withAnimation {
            store.move(item, toDay: day, in: trip, before: nil)
            store.save()
        }
    }

    /// Handles a drop of dragged item IDs onto a day (nil = wish list), before `target` or at the end.
    private func drop(_ ids: [String], onto day: Day?, before target: Item?) -> Bool {
        let items = ids.compactMap { id in trip.allItems.first { $0.uuid?.uuidString == id } }
        guard !items.isEmpty else { return false }
        withAnimation {
            for item in items where item != target {
                store.move(item, toDay: day, in: trip, before: target)
            }
            store.save()
        }
        return true
    }
}

/// Which list a new item should start in (`day == nil` means the wish list).
struct NewItemTarget: Identifiable {
    let id = UUID()
    let day: Day?
}

// MARK: - Pieces

private struct DropPlaceholder: View {
    let text: String
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 4)
            .listRowBackground(isTargeted ? Theme.mango.opacity(0.15) : Theme.cardBackground)
            .dropDestination(for: String.self) { ids, _ in
                onDrop(ids)
            } isTargeted: { isTargeted = $0 }
    }
}

private struct DayHeader: View {
    @ObservedObject var day: Day
    let onMap: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Day \(day.number)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let date = day.date {
                    Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let date = day.date, Calendar.current.isDateInToday(date) {
                Text("TODAY")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.lagoon, in: Capsule())
            }
            Spacer()
            Button(action: onMap) {
                Image(systemName: "map")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 36)
            }
            .accessibilityLabel("Map of day \(day.number)")
            .disabled(!day.sortedItems.contains { $0.hasCoordinate })
            Button(action: onAdd) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 36)
            }
            .accessibilityLabel("Add to day \(day.number)")
        }
        .textCase(nil)
    }
}

/// Trip name, dates, countdown and quick links.
private struct TripHeaderCard: View {
    @ObservedObject var trip: Trip
    let onPacking: () -> Void
    let onIdeas: () -> Void

    private var countdown: String {
        guard let start = trip.startDate, let end = trip.endDate else { return "" }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if today < start {
            let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
            return days == 1 ? "Starts tomorrow" : "Starts in \(days) days"
        } else if today <= end, let day = trip.today {
            return "Day \(day.number) of \(trip.sortedDays.count)"
        } else {
            return "Trip complete"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(countdown.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(trip.displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                if let start = trip.startDate, let end = trip.endDate {
                    Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            let all = trip.allItems
            HStack(spacing: 8) {
                HeaderChip(systemImage: "calendar", text: "\(trip.sortedDays.count) days")
                HeaderChip(systemImage: "mappin", text: "\(all.count) places")
                HeaderChip(systemImage: "ticket", text: "\(all.filter { $0.status == .booked }.count) booked")
            }

            HStack(spacing: 10) {
                Button(action: onPacking) {
                    let packing = trip.sortedPackingItems
                    Label("Packing \(packing.filter(\.isDone).count)/\(packing.count)", systemImage: "suitcase.rolling.fill")
                }
                Button(action: onIdeas) {
                    Label("Starter Ideas", systemImage: "lightbulb.fill")
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(HeaderButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunsetGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 54))
                .foregroundStyle(.white.opacity(0.18))
                .padding(14)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }
}

private struct HeaderChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.2), in: Capsule())
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.mango)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(.white, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview {
    NavigationStack {
        TripTabView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
