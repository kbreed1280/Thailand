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
    @State private var showingEntry = false
    @State private var showingRecap = false
    @State private var showingConverter = false
    @State private var showingTransit = false
    @State private var showingOffline = false
    @State private var sharingError: String?
    @AppStorage("plannerTab") private var tabRaw = PlannerTab.overview.rawValue
    @State private var showingBudget = false
    @State private var showingAssistant = false
    @State private var showingNewList = false
    @State private var newListName = ""
    @State private var renamingList: String?
    @State private var renameText = ""
    @State private var optimizeMessage: String?
    @State private var collapsedLists: Set<String> = []

    private var tab: PlannerTab { PlannerTab(rawValue: tabRaw) ?? .overview }

    private var store: ItineraryStore { ItineraryStore(context: context) }
    private var persistence: PersistenceController { PersistenceController.shared }
    /// False when the trip's owner gave you view-only access.
    private var canEdit: Bool { persistence.canEdit(trip) }

    var body: some View {
        // Re-read relationships whenever anything in the store changes (local edits or sync).
        let _ = refreshTick
        plannerContent
            .safeAreaInset(edge: .top, spacing: 0) { tabPicker }
            .skyBackground()
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
            ItemEditorView(item: nil, trip: trip, initialDay: target.day, initialList: target.list)
        }
        .sheet(isPresented: $showingBudget) { BudgetView(trip: trip) }
        .sheet(isPresented: $showingAssistant) { TripAssistantView(trip: trip) }
        .alert("New List", isPresented: $showingNewList) {
            TextField("Restaurants, Things to do…", text: $newListName)
            Button("Create") {
                store.addList(newListName, to: trip)
                store.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ideas: \(TripLists.suggestions.prefix(4).joined(separator: ", ")).")
        }
        .alert("Rename List", isPresented: Binding(get: { renamingList != nil }, set: { if !$0 { renamingList = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let old = renamingList {
                    store.renameList(old, to: renameText, in: trip)
                    store.save()
                }
                renamingList = nil
            }
            Button("Cancel", role: .cancel) { renamingList = nil }
        }
        .alert("Route Optimized", isPresented: Binding(get: { optimizeMessage != nil }, set: { if !$0 { optimizeMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(optimizeMessage ?? "")
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
            ExchangeRateStore.shared.useTrip(trip)
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
        .sheet(isPresented: $showingEntry) { EntryRequirementsView(trip: trip) }
        .sheet(isPresented: $showingRecap) { TripRecapView(trip: trip) }
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

    // MARK: Tabs

    private var tabPicker: some View {
        Picker("Planner section", selection: $tabRaw) {
            ForEach(PlannerTab.allCases) { tab in
                Text(tab.title).tag(tab.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var plannerContent: some View {
        switch tab {
        case .map:
            TripMapView(trip: trip) { mapDay = $0 }
        case .overview, .itinerary:
            List {
                if tab == .overview {
                    overviewSections
                } else {
                    itinerarySections
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var overviewSections: some View {
        Section {
            TripHero(
                trip: trip,
                members: persistence.participantNames(for: trip),
                isSharedWithMe: persistence.isSharedWithMe(trip),
                canEdit: canEdit,
                onFlights: { showingFlights = true },
                onWeather: { showingWeather = true },
                onShare: persistence.isCloudEnabled ? { shareTrip() } : nil,
                isPreparingShare: isPreparingShare
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
            AssistantCard { showingAssistant = true }
        }

        Section {
            TravelToolsGrid(trip: trip) { tool in
                switch tool {
                case .packing: showingPacking = true
                case .documents: showingVault = true
                case .flights: showingFlights = true
                case .weather: showingWeather = true
                case .tdac: showingTDAC = true
                case .entry: showingEntry = true
                case .converter: showingConverter = true
                case .transit: showingTransit = true
                case .offline: showingOffline = true
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        Section {
            BookingsSummaryRow(trip: trip, canEdit: canEdit,
                               onOpen: { showingBookings = true },
                               onImport: { showingImport = true })
            BudgetCard(trip: trip) { showingBudget = true }
        }

        Section {
            TripNotesCard(trip: trip, canEdit: canEdit)
        }

        wishListSection

        ForEach(trip.customListNames, id: \.self) { name in
            customListSection(name)
        }

        Section {
            if canEdit {
                Button {
                    newListName = ""
                    showingNewList = true
                } label: {
                    Label("New List", systemImage: "plus.rectangle.on.rectangle")
                }
            }
            ExportMapsRow(trip: trip)
        } footer: {
            Text("Lists hold places you haven't scheduled, like Restaurants or Things to do. Drag a place onto a day in Itinerary when you're ready.")
        }
    }

    @ViewBuilder
    private var itinerarySections: some View {
        if trip.sortedDays.isEmpty {
            Section {
                Text("Add travel dates to the trip to get a plan for each day.")
                    .foregroundStyle(.secondary)
                Button("Edit Trip", systemImage: "calendar") { showingEditTrip = true }
                    .disabled(!canEdit)
            }
        }
        ForEach(trip.sortedDays) { day in
            daySection(day)
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

    private func customListSection(_ name: String) -> some View {
        let expanded = !collapsedLists.contains(name)
        let items = trip.listItems(name)
        return Section {
            if expanded {
                if items.isEmpty {
                    DropPlaceholder(text: "Drag places here, or tap + to add one.") { ids in
                        drop(ids, onto: nil, list: name, before: nil)
                    }
                }
                ForEach(items) { item in
                    row(for: item, in: nil, list: name)
                }
            }
        } header: {
            HStack {
                Button {
                    withAnimation {
                        if expanded { collapsedLists.insert(name) } else { collapsedLists.remove(name) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.fill").foregroundStyle(Theme.lagoon)
                        Text(name).font(.title3.weight(.bold))
                        Text("\(items.count)").foregroundStyle(.secondary)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name), \(items.count) places, \(expanded ? "expanded" : "collapsed")")
                Spacer()
                if canEdit {
                    Menu {
                        Button("Add a Place", systemImage: "plus") {
                            editingNewItemFor = NewItemTarget(day: nil, list: name)
                        }
                        Button("Rename", systemImage: "pencil") {
                            renameText = name
                            renamingList = name
                        }
                        Button("Delete List", systemImage: "trash", role: .destructive) {
                            withAnimation {
                                store.deleteList(name, in: trip)
                                store.save()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 32)
                    }
                    .accessibilityLabel("\(name) options")
                }
            }
            .font(.headline)
            .textCase(nil)
            .foregroundStyle(.primary)
            .dropDestination(for: String.self) { ids, _ in
                drop(ids, onto: nil, list: name, before: nil)
            }
        }
    }

    private func optimize(_ day: Day) {
        let hotel = trip.sortedSavedPlaces.first
        let saved = store.optimizeRoute(for: day, start: hotel?.coordinate, end: hotel?.coordinate)
        store.save()
        if saved > 0 {
            let km = saved / 1000
            let distance = km >= 1 ? String(format: "%.1f km", km) : "\(Int(saved.rounded())) m"
            let timed = day.sortedItems.contains { $0.time != nil }
            optimizeMessage = "Day \(day.number) reordered\(hotel.map { " from \($0.displayName)" } ?? ""), about \(distance) shorter."
                + (timed ? " Start times weren't changed: open Map & route and tap Re-time Day to update them." : "")
        } else {
            optimizeMessage = "Day \(day.number) is already in the shortest order."
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
            DayHeader(day: day, canAddSpots: canEdit && !trip.confirmedSpots.isEmpty, canEdit: canEdit) {
                mapDay = day
            } onAdd: {
                editingNewItemFor = NewItemTarget(day: day)
            } onSpots: {
                spotPickerDay = day
            } onOptimize: {
                optimize(day)
            }
            .dropDestination(for: String.self) { ids, _ in
                drop(ids, onto: day, before: nil)
            }
        }
    }

    @ViewBuilder
    private func row(for item: Item, in day: Day?, list: String = "") -> some View {
        if canEdit {
            editableRow(for: item, in: day, list: list)
        } else {
            NavigationLink(value: item) {
                ItemRow(item: item)
            }
        }
    }

    private func editableRow(for item: Item, in day: Day?, list: String = "") -> some View {
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
            drop(ids, onto: day, list: list, before: item)
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
                ForEach(trip.customListNames, id: \.self) { name in
                    Button(name, systemImage: "list.bullet") { move(item, to: nil, list: name) }
                }
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
            if trip.isThailand {
                Button("Starter Ideas", systemImage: "lightbulb") { showingStarterIdeas = true }
            }
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
            Button("Entry Requirements", systemImage: "checkmark.seal") { showingEntry = true }
            Button("Trip Recap", systemImage: "sparkles.rectangle.stack") { showingRecap = true }
            if trip.isThailand {
                Button("Arrival Card (TDAC)", systemImage: "person.text.rectangle") { showingTDAC = true }
            }
            Button("\(CurrencyContext.shortName(trip.localCurrency)) Converter", systemImage: Destinations.symbolName(forCurrency: trip.localCurrency)) { showingConverter = true }
            Button("Offline Maps", systemImage: "arrow.down.circle") { showingOffline = true }
            if trip.isThailand {
                Button("BTS & MRT", systemImage: "tram.fill") { showingTransit = true }
            }
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

    private func move(_ item: Item, to day: Day?, list: String = "") {
        withAnimation {
            store.move(item, toDay: day, in: trip, before: nil)
            if day == nil { item.listName = list }
            store.save()
        }
    }

    /// Handles a drop of dragged item IDs onto a day (nil = wish list), before `target` or at the end.
    private func drop(_ ids: [String], onto day: Day?, list: String = "", before target: Item?) -> Bool {
        let items = ids.compactMap { id in trip.allItems.first { $0.uuid?.uuidString == id } }
        guard !items.isEmpty else { return false }
        withAnimation {
            for item in items where item != target {
                store.move(item, toDay: day, in: trip, before: target)
                if day == nil, item.listName != list {
                    item.listName = list
                    item.markEdited()
                }
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
    /// Custom list for a new unscheduled place ("" = Wish List).
    var list: String = ""
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
    var canEdit = true
    let onMap: () -> Void
    let onAdd: () -> Void
    var onSpots: () -> Void = {}
    var onOptimize: () -> Void = {}
    @State private var walked: WalkStats?
    @State private var totals: TravelLeg?

    /// Changes whenever the day's stops, order or travel modes change.
    private var totalsKey: String {
        day.sortedItems.filter(\.hasCoordinate)
            .map { String(format: "%.5f,%.5f,%@", $0.latitude, $0.longitude, $0.travelModeRaw ?? "") }
            .joined(separator: ";")
    }
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
                    if let totals, totals.seconds > 0 {
                        Label("\(ScheduleMath.durationText(seconds: totals.seconds)) · \(Self.distanceText(totals.meters))", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .foregroundStyle(Theme.ink)
                            .accessibilityLabel("Travel today: \(ScheduleMath.durationText(seconds: totals.seconds)), \(Self.distanceText(totals.meters))")
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
                    Text("\(Temperature.deg(w.highC))").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(w.heatLevel.color.opacity(0.14), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("High \(Temperature.f(w.highC)) degrees, feels like \(Temperature.f(w.maxHeatIndexC)), \(w.heatLevel.title)")
            }
            Menu {
                Button("Add a stop", systemImage: "plus", action: onAdd)
                if canAddSpots { Button("Add from Spots", systemImage: "mappin.and.ellipse", action: onSpots) }
                Button("Map & route", systemImage: "map", action: onMap)
                    .disabled(!day.sortedItems.contains { $0.hasCoordinate })
                if canEdit {
                    Button("Optimize Route", systemImage: "arrow.triangle.swap", action: onOptimize)
                        .disabled(day.sortedItems.filter(\.hasCoordinate).count < 2)
                }
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
        .task(id: totalsKey) { totals = await dayTotals() }
    }

    /// Total travel time and distance between the day's stops, by each stop's travel mode.
    private func dayTotals() async -> TravelLeg? {
        let stops = day.sortedItems.filter(\.hasCoordinate)
        guard stops.count > 1 else { return nil }
        var total = TravelLeg(seconds: 0, meters: 0)
        for (from, to) in zip(stops, stops.dropFirst()) {
            guard let a = from.coordinate, let b = to.coordinate,
                  let leg = await TravelTimeService.shared.leg(from: a, to: b, mode: to.travelMode, at: to.time) else { continue }
            total.seconds += leg.seconds
            total.meters += leg.meters
        }
        return total.seconds > 0 ? total : nil
    }

    static func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
    }
}

#Preview {
    NavigationStack {
        TripTabView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
