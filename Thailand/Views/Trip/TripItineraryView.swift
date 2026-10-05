import SwiftUI
import CoreData
import EventKit

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
    @State private var showingAutoPlan = false
    @State private var showingSidequest = false
    @State private var confirmingDelete = false
    @State private var mapDay: Day?
    @State private var spotPickerDay: Day?
    @State private var isPreparingShare = false
    @State private var showingEmergency = false
    @State private var showingSavedPlaces = false
    @State private var showingBookings = false
    @State private var showingImport = false
    @State private var showingCalendar = false
    @State private var showingBook = false
    @ObservedObject private var calendarSync = CalendarSyncService.shared
    @State private var walkTarget: WalkTarget?
    @State private var showingVault = false
    @State private var showingFlights = false
    @State private var showingWeather = false
    @State private var showingTDAC = false
    @State private var showingConverter = false
    @State private var showingTransit = false
    @State private var showingOffline = false
    @State private var sharingError: String?

    private var store: ItineraryStore { ItineraryStore(context: context) }
    private var persistence: PersistenceController { PersistenceController.shared }
    /// False when the trip's owner gave you view-only access.
    private var canEdit: Bool { persistence.canEdit(trip) }

    var body: some View {
        // Re-read relationships whenever anything in the store changes (local edits or sync).
        let _ = refreshTick
        List {
            Section {
                TripHero(
                    trip: trip,
                    members: persistence.participantNames(for: trip),
                    isSharedWithMe: persistence.isSharedWithMe(trip),
                    canEdit: canEdit,
                    onFlights: { showingFlights = true },
                    onWeather: { showingWeather = true }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                TodayCard(trip: trip,
                          onDirections: { item in
                              if let c = item.coordinate { walkTarget = WalkTarget(name: item.displayTitle, coordinate: c) }
                          },
                          onOpenDay: { mapDay = $0 },
                          onAddSpots: { spotPickerDay = $0 },
                          onSidequest: { showingSidequest = true })
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                TravelToolsGrid(trip: trip) { tool in
                    switch tool {
                    case .packing: showingPacking = true
                    case .documents: showingVault = true
                    case .flights: showingFlights = true
                    case .weather: showingWeather = true
                    case .tdac: showingTDAC = true
                    case .converter: showingConverter = true
                    case .transit: showingTransit = true
                    case .offline: showingOffline = true
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            wishListSection

            ForEach(trip.sortedDays) { day in
                daySection(day)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(trip.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu { tripMenu }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if persistence.isCloudEnabled {
                    Button {
                        shareTrip()
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                        } else {
                            Image(systemName: persistence.share(for: trip) == nil ? "person.crop.circle.badge.plus" : "person.2.circle.fill")
                                .font(.title3)
                        }
                    }
                    .accessibilityLabel("Share Trip")
                    .disabled(isPreparingShare)
                }
                if canEdit {
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
        }
        .alert("Couldn't Share", isPresented: Binding(get: { sharingError != nil }, set: { if !$0 { sharingError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharingError ?? "")
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
        .sheet(item: $spotPickerDay) { day in
            SpotPickerSheet(trip: trip, day: day)
        }
        .sheet(isPresented: $showingAutoPlan) {
            AutoPlanView(trip: trip)
        }
        .fullScreenCover(isPresented: $showingSidequest) {
            SidequestView(trip: trip)
        }
        .task(id: trip.objectID) {
            await TripForecast.shared.refresh(trip)
            await DayReminders.reschedule(for: trip)
        }
        .sheet(isPresented: $showingEmergency) {
            EmergencyView(trip: trip)
        }
        .sheet(isPresented: $showingSavedPlaces) {
            SavedPlacesView(trip: trip)
        }
        .sheet(isPresented: $showingBookings) {
            BookingsView(trip: trip)
        }
        .sheet(isPresented: $showingImport) {
            SmartImportView(trip: trip)
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarSettingsView(trip: trip)
        }
        .sheet(isPresented: $showingBook) {
            TripBookView(trip: trip)
        }
        .fullScreenCover(item: $walkTarget) { target in
            WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
        }
        .sheet(isPresented: $showingVault) {
            DocumentVaultView(trip: trip)
        }
        .sheet(isPresented: $showingFlights) {
            FlightsView(trip: trip)
        }
        .sheet(isPresented: $showingWeather) {
            WeatherSheet()
        }
        .sheet(isPresented: $showingTDAC) {
            TDACView(trip: trip)
        }
        .sheet(isPresented: $showingConverter) {
            ConvertTabView(showsDone: true)
        }
        .sheet(isPresented: $showingTransit) {
            NavigationStack {
                BangkokTransitView(trip: trip)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showingTransit = false } }
                    }
            }
        }
        .sheet(isPresented: $showingOffline) {
            OfflinePackView(trip: trip)
        }
        .sheet(item: $mapDay) { day in
            DayMapView(day: day)
        }
        .confirmationDialog(
            persistence.isSharedWithMe(trip) ? "Leave \(trip.displayName)?" : "Delete \(trip.displayName)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            if persistence.isSharedWithMe(trip) {
                Button("Leave Trip", role: .destructive) {
                    Task {
                        try? await persistence.leave(trip)
                        selectedTripID = ""
                    }
                }
            } else {
                Button("Delete Trip", role: .destructive) {
                    store.delete(trip)
                    store.save()
                    selectedTripID = ""
                }
            }
        } message: {
            if persistence.isSharedWithMe(trip) {
                Text("The trip is removed from your phone. The owner and others keep it.")
            } else if persistence.share(for: trip) != nil {
                Text("This trip is shared. Deleting it removes it for everyone you shared it with.")
            } else {
                Text("Every day, place, photo, expense and packing item in this trip is deleted.")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var wishListSection: some View {
        Section {
            if wishListExpanded {
                let items = trip.wishListPlaces
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
                        
                        Text("Wish List").font(.title3.weight(.bold))
                        Text("\(trip.wishListPlaces.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: wishListExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wish list, \(trip.wishListPlaces.count) places, \(wishListExpanded ? "expanded" : "collapsed")")
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
                EmptyDayRow(canAddSpots: canEdit && !trip.confirmedSpots.isEmpty,
                            onSpots: { spotPickerDay = day },
                            onAdd: { editingNewItemFor = NewItemTarget(day: day) },
                            onDrop: { ids in drop(ids, onto: day, before: nil) })
            }
            ForEach(Array(items.enumerated()), id: \.element.objectID) { index, item in
                if index > 0, items[index - 1].hasCoordinate, item.hasCoordinate {
                    LegRow(from: items[index - 1], to: item) { walkTarget = $0 }
                }
                row(for: item, in: day)
            }
            if let date = day.date {
                let _ = calendarSync.changeTick
                ForEach(calendarSync.events(on: date), id: \.calendarItemIdentifier) { event in
                    CalendarEventRow(event: event)
                        .contextMenu {
                            if canEdit {
                                Button("Add to This Day", systemImage: "plus") { addCalendarEvent(event, to: day) }
                            }
                        }
                }
            }
        } header: {
            DayHeader(day: day, canAddSpots: canEdit && !trip.confirmedSpots.isEmpty) {
                mapDay = day
            } onAdd: {
                editingNewItemFor = NewItemTarget(day: day)
            } onSpots: {
                spotPickerDay = day
            }
            .dropDestination(for: String.self) { ids, _ in
                drop(ids, onto: day, before: nil)
            }
        }
    }

    @ViewBuilder
    private func row(for item: Item, in day: Day?) -> some View {
        if canEdit {
            editableRow(for: item, in: day)
        } else {
            NavigationLink(value: item) {
                ItemRow(item: item)
            }
        }
    }

    private func editableRow(for item: Item, in day: Day?) -> some View {
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
            if persistence.isCloudEnabled {
                Button("Share Trip", systemImage: "person.crop.circle.badge.plus") { shareTrip() }
            }
            Button("Edit Trip", systemImage: "pencil") { showingEditTrip = true }
                .disabled(!canEdit)
            Button("Packing List", systemImage: "suitcase.rolling") { showingPacking = true }
            Button("Saved Places", systemImage: "mappin.and.ellipse") { showingSavedPlaces = true }
            Button("Bookings", systemImage: "doc.text.fill") { showingBookings = true }
            Button("Import a Booking", systemImage: "wand.and.stars") { showingImport = true }
                .disabled(!canEdit)
            Button("Calendar", systemImage: "calendar") { showingCalendar = true }
            Button("Trip Book", systemImage: "book.pages.fill") { showingBook = true }
            Button("Starter Ideas", systemImage: "lightbulb") { showingStarterIdeas = true }
            Button("Auto-plan Days", systemImage: "wand.and.sparkles") { showingAutoPlan = true }
                .disabled(!canEdit)
            Button("Sidequest", systemImage: "dice") { showingSidequest = true }
            Button("Profile", systemImage: "person.crop.circle") { showingProfile = true }
        }
        Section {
            Button("Emergency Info", systemImage: "cross.case.fill") { showingEmergency = true }
            Button("Travel Documents", systemImage: "lock.doc.fill") { showingVault = true }
            Button("Flights", systemImage: "airplane") { showingFlights = true }
            Button("Weather", systemImage: "sun.max.fill") { showingWeather = true }
            Button("Arrival Card (TDAC)", systemImage: "person.text.rectangle") { showingTDAC = true }
            Button("Baht Converter", systemImage: "bahtsign.circle") { showingConverter = true }
            Button("Offline Maps", systemImage: "arrow.down.circle") { showingOffline = true }
            Button("BTS & MRT", systemImage: "tram.fill") { showingTransit = true }
        }
        Section {
            Button("New Trip", systemImage: "plus") { showingNewTrip = true }
            Button(
                persistence.isSharedWithMe(trip) ? "Leave Trip" : "Delete Trip",
                systemImage: persistence.isSharedWithMe(trip) ? "rectangle.portrait.and.arrow.right" : "trash",
                role: .destructive
            ) { confirmingDelete = true }
        }
    }

    private func addCalendarEvent(_ event: EKEvent, to day: Day) {
        let item = store.addItem(
            title: event.title ?? "Event",
            category: .activity,
            to: day,
            in: trip,
            address: event.location ?? "",
            notes: event.notes ?? ""
        )
        item.time = event.isAllDay ? nil : event.startDate
        if let start = event.startDate, let end = event.endDate, !event.isAllDay {
            item.durationMinutes = Int64(max(15, end.timeIntervalSince(start) / 60))
        }
        store.save()
    }

    private func shareTrip() {
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            do {
                try await TripSharing.presentShareSheet(for: trip)
            } catch {
                sharingError = error.localizedDescription
            }
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
    var canAddSpots = false
    let onMap: () -> Void
    let onAdd: () -> Void
    var onSpots: () -> Void = {}
    @State private var walked: WalkStats?
    @ObservedObject private var forecast = TripForecast.shared

    private var isToday: Bool { day.date.map { Calendar.current.isDateInToday($0) } ?? false }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Day \(day.number)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    if isToday {
                        Text("TODAY")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.ink, in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    if let date = day.date {
                        Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    }
                    if let walked, walked.steps > 0 {
                        Label("\(walked.steps.formatted()) steps", systemImage: "shoeprints.fill")
                            .foregroundStyle(Theme.lagoon)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let date = day.date, let trip = day.trip, let w = forecast.day(date, in: trip) {
                HStack(spacing: 5) {
                    Image(systemName: w.symbolName).symbolRenderingMode(.multicolor)
                    Text("\(Int(w.highC.rounded()))°").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(w.heatLevel.color.opacity(0.14), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("High \(Int(w.highC.rounded())) degrees, feels like \(Int(w.maxHeatIndexC.rounded())), \(w.heatLevel.title)")
            }
            Menu {
                Button("Add a stop", systemImage: "plus", action: onAdd)
                if canAddSpots { Button("Add from Spots", systemImage: "mappin.and.ellipse", action: onSpots) }
                Button("Map & route", systemImage: "map", action: onMap)
                    .disabled(!day.sortedItems.contains { $0.hasCoordinate })
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 44, minHeight: 40)
            }
            .accessibilityLabel("Day \(day.number) actions")
        }
        .textCase(nil)
        .padding(.top, 10)
        .task(id: day.date) {
            if let date = day.date {
                walked = await PedometerService.shared.stats(for: date)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TripTabView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
