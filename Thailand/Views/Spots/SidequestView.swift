import CoreData
import MapKit
import SwiftUI

/// Sidequests: pick a city (or "near me") and what you're in the mood for, swipe through
/// places (your saved spots plus Apple Maps finds), then get the shortest walking route
/// through the ones you kept. Save them, add them to a day, or open the route in Maps.
struct SidequestView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    enum Stage { case setup, swiping, route }

    struct Card: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
        let category: SpotCategory
        let mapItem: MKMapItem?
        let spot: Spot?
        static func == (a: Card, b: Card) -> Bool { a.id == b.id }
    }

    @State private var stage: Stage = .setup
    @State private var cityName = WeatherPlace.cities[0].name
    @State private var useMyLocation = false
    @State private var moods: Set<SpotCategory> = [.eat, .brew, .explore]
    @State private var cards: [Card] = []
    @State private var kept: [Card] = []
    @State private var index = 0
    @State private var loading = false
    @State private var center = WeatherPlace.cities[0].location.coordinate
    @State private var route: [Card] = []
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .setup: setup
                case .swiping: swiping
                case .route: routeView
                }
            }
            .background(Theme.background)
            #if DEBUG
            // Debug-only: `-showSidequest YES` starts the deck right away, for screenshots.
            .task { if UserDefaults.standard.bool(forKey: "showSidequest"), stage == .setup { await loadCards() } }
            #endif
            .navigationTitle("Sidequest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if stage == .swiping, !kept.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("Route (\(kept.count))") { buildRoute() } }
                }
            }
        }
    }

    // MARK: Setup

    private var setup: some View {
        Form {
            Section("Where") {
                Toggle("Near me", isOn: $useMyLocation)
                if !useMyLocation {
                    Picker("City", selection: $cityName) {
                        ForEach(WeatherPlace.cities) { Text($0.name).tag($0.name) }
                    }
                }
            }
            Section {
                ForEach(SpotCategory.allCases.filter { $0 != .go && $0 != .stay }) { c in
                    Button {
                        if moods.contains(c) { moods.remove(c) } else { moods.insert(c) }
                    } label: {
                        HStack {
                            Image(systemName: c.systemImage).foregroundStyle(.white)
                                .frame(width: 28, height: 28).background(c.color, in: Circle())
                            VStack(alignment: .leading) {
                                Text(c.title).foregroundStyle(.primary)
                                Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if moods.contains(c) { Image(systemName: "checkmark").foregroundStyle(Theme.mango) }
                        }
                    }
                }
            } header: {
                Text("In the mood for")
            } footer: {
                Text("Swipe right to keep, left to skip. Your saved spots nearby show up too.")
            }
            Section {
                Button {
                    Task { await loadCards() }
                } label: {
                    HStack {
                        Spacer()
                        if loading { ProgressView() } else { Label("Start sidequest", systemImage: "sparkles").font(.headline) }
                        Spacer()
                    }
                }
                .disabled(moods.isEmpty || loading)
            }
        }
    }

    // MARK: Swiping

    private var swiping: some View {
        VStack(spacing: 16) {
            Text(index < cards.count ? "\(index + 1) of \(cards.count) · \(kept.count) kept" : "\(kept.count) kept")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack {
                if index < cards.count {
                    ForEach(Array(cards.enumerated().filter { $0.offset >= index && $0.offset < index + 2 }.reversed()), id: \.element.id) { offset, card in
                        SwipeCard(card: card, center: center, isTop: offset == index) { keep in decide(card, keep: keep) }
                    }
                } else {
                    ContentUnavailableView {
                        Label("That's everything", systemImage: "checkmark.seal")
                    } description: {
                        Text(kept.isEmpty ? "Nothing kept. Try other moods." : "Build your route from the \(kept.count) you kept.")
                    } actions: {
                        if kept.isEmpty {
                            Button("Start over") { stage = .setup }
                        } else {
                            Button("Build route") { buildRoute() }.buttonStyle(.borderedProminent).tint(Theme.mango)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if index < cards.count {
                HStack(spacing: 40) {
                    Button { decide(cards[index], keep: false) } label: {
                        Image(systemName: "xmark").font(.title.weight(.bold)).frame(width: 64, height: 64)
                            .background(.regularMaterial, in: Circle()).foregroundStyle(Theme.coral)
                    }
                    .accessibilityLabel("Skip")
                    Button { decide(cards[index], keep: true) } label: {
                        Image(systemName: "heart.fill").font(.title.weight(.bold)).frame(width: 64, height: 64)
                            .background(.regularMaterial, in: Circle()).foregroundStyle(Theme.lagoon)
                    }
                    .accessibilityLabel("Keep")
                }
            }
        }
        .padding()
    }

    private func decide(_ card: Card, keep: Bool) {
        withAnimation(.spring(duration: 0.3)) {
            if keep { kept.append(card) }
            index += 1
        }
    }

    // MARK: Route

    private var routeView: some View {
        let stops = route.map { AutoPlanner.Stop(id: $0.id, name: $0.name, coordinate: $0.coordinate, category: $0.category) }
        let meters = AutoPlanner.routeLength(stops)
        return List {
            Section {
                Map(initialPosition: .automatic) {
                    MapPolyline(coordinates: route.map(\.coordinate)).stroke(Theme.mango, lineWidth: 4)
                    ForEach(Array(route.enumerated()), id: \.element.id) { i, card in
                        Annotation(card.name, coordinate: card.coordinate) {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(card.category.color, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("\(route.count) stops · \(String(format: "%.1f", meters / 1000)) km between them · about \(ScheduleMath.durationText(seconds: meters * 1.3 / 1.2)) on foot")
            }
            Section("Order") {
                ForEach(Array(route.enumerated()), id: \.element.id) { i, card in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.headline.monospacedDigit()).frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(card.name).font(.subheadline.weight(.semibold))
                            Text(card.spot != nil ? "Saved spot" : card.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onMove { route.move(fromOffsets: $0, toOffset: $1) }
            }
            Section {
                Button("Open in Google Maps", systemImage: "map") { ExternalApps.openGoogleMaps(stops: route.map(\.coordinate)) }
                Button("Open in Apple Maps", systemImage: "apple.logo") {
                    ExternalApps.openAppleMapsRoute(route.map { ($0.name, $0.coordinate) }, walking: true)
                }
                Button("Save stops to Spots", systemImage: "mappin.and.ellipse") { _ = saveSpots(); savedMessage = "Saved to Spots" }
                if !trip.sortedDays.isEmpty {
                    Menu {
                        ForEach(trip.sortedDays) { day in
                            Button("Day \(day.number)" + (day.date.map { " · " + $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "")) {
                                addToDay(day)
                            }
                        }
                    } label: { Label("Add route to a day", systemImage: "calendar.badge.plus") }
                }
            } footer: {
                if let savedMessage { Text(savedMessage).foregroundStyle(Theme.lagoon) }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private func buildRoute() {
        let stops = kept.map { AutoPlanner.Stop(id: $0.id, name: $0.name, coordinate: $0.coordinate, category: $0.category) }
        let start = useMyLocation ? LocationService.shared.lastLocation?.coordinate : nil
        let ordered = AutoPlanner.shortestRoute(stops, from: start)
        route = ordered.compactMap { s in kept.first { $0.id == s.id } }
        stage = .route
    }

    /// Creates Spots for Apple Maps finds (saved spots are reused).
    private func saveSpots() -> [Spot] {
        var result: [Spot] = []
        for (i, card) in route.enumerated() {
            if let spot = card.spot { result.append(spot); continue }
            let existing = ImportPipeline.existingSpot(name: card.name, coordinate: card.coordinate,
                                                       appleMapsID: card.mapItem?.identifier?.rawValue, in: trip.allSpots)
            let spot = existing ?? Spot(context: context)
            if existing == nil {
                spot.placeInSameStore(as: trip)
                spot.uuid = UUID()
                spot.status = .confirmed
                spot.addedBy = AppSettings.displayName
                spot.createdAt = .now
                spot.trip = trip
                if let item = card.mapItem { spot.apply(item) } else { spot.name = card.name; spot.coordinate = card.coordinate }
                spot.notes = "Found on a sidequest"
            }
            route[i] = Card(name: card.name, address: card.address, coordinate: card.coordinate, category: card.category, mapItem: card.mapItem, spot: spot)
            result.append(spot)
        }
        ItineraryStore(context: context).save()
        return result
    }

    private func addToDay(_ day: Day) {
        let spots = saveSpots()
        let store = ItineraryStore(context: context)
        let stops = route.map { AutoPlanner.Stop(id: $0.id, name: $0.name, coordinate: $0.coordinate, category: $0.category) }
        let date = day.date ?? .now
        var clock = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? date
        for (i, spot) in spots.enumerated() {
            if i > 0 { clock = ScheduleMath.roundedUpToFiveMinutes(clock.addingTimeInterval(AutoPlanner.travelSeconds(from: stops[i - 1].coordinate, to: stops[i].coordinate))) }
            let item = store.addItem(title: spot.displayName, category: AutoPlanView.itemCategory(spot.category), to: day, in: trip,
                                     address: spot.address ?? "", coordinate: spot.coordinate, notes: AutoPlanView.notes(for: spot))
            let minutes = AutoPlanner.duration(for: spot.category)
            item.time = clock
            item.durationMinutes = Int64(minutes)
            item.travelModeRaw = "walking"
            clock = clock.addingTimeInterval(TimeInterval(minutes * 60))
        }
        store.save()
        savedMessage = "Added \(spots.count) stops to Day \(day.number)"
    }

    // MARK: Loading cards

    private static func queries(for c: SpotCategory) -> [String] {
        switch c {
        case .eat: ["street food", "local restaurant"]
        case .brew: ["specialty coffee", "café"]
        case .sip: ["rooftop bar", "cocktail bar"]
        case .vibe: ["market", "spa", "boutique"]
        case .explore: ["temple", "museum", "viewpoint"]
        case .go: ["tour"]
        case .stay: ["hotel"]
        }
    }

    private func loadCards() async {
        loading = true
        defer { loading = false }
        if useMyLocation, let here = await LocationService.shared.currentLocation() {
            center = here.coordinate
        } else {
            center = (WeatherPlace.cities.first { $0.name == cityName } ?? WeatherPlace.cities[0]).location.coordinate
        }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let radius: CLLocationDistance = 3_000

        var found: [Card] = trip.confirmedSpots.compactMap { spot in
            guard let c = spot.coordinate, moods.contains(spot.category),
                  CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: here) < radius else { return nil }
            return Card(name: spot.displayName, address: spot.address ?? "", coordinate: c, category: spot.category, mapItem: nil, spot: spot)
        }
        var names = Set(found.map { $0.name.localizedLowercase })
        await withTaskGroup(of: [(SpotCategory, MKMapItem)].self) { group in
            for mood in moods {
                for q in Self.queries(for: mood) {
                    group.addTask {
                        let request = MKLocalSearch.Request()
                        request.naturalLanguageQuery = q
                        request.resultTypes = .pointOfInterest
                        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
                        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
                        return items.prefix(6).map { (mood, $0) }
                    }
                }
            }
            var perMood: [SpotCategory: [MKMapItem]] = [:]
            for await batch in group { for (mood, item) in batch { perMood[mood, default: []].append(item) } }
            // Interleave moods so the deck isn't ten cafés in a row.
            var round = 0
            while perMood.values.contains(where: { round < $0.count }) {
                for mood in SpotCategory.allCases {
                    guard let items = perMood[mood], round < items.count else { continue }
                    let item = items[round]
                    guard let name = item.name, !names.contains(name.localizedLowercase),
                          (item.placemark.location?.distance(from: here) ?? .infinity) < radius * 1.2 else { continue }
                    names.insert(name.localizedLowercase)
                    found.append(Card(name: name, address: item.placemark.title ?? "", coordinate: item.placemark.coordinate,
                                      category: mood, mapItem: item, spot: nil))
                }
                round += 1
            }
        }
        cards = Array(found.prefix(30))
        kept = []
        index = 0
        stage = .swiping
    }
}

// MARK: - Card

private struct SwipeCard: View {
    let card: SidequestView.Card
    let center: CLLocationCoordinate2D
    let isTop: Bool
    let onDecide: (Bool) -> Void
    @State private var drag: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(center: card.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)),
                interactionModes: []) {
                Marker(card.name, systemImage: card.category.systemImage, coordinate: card.coordinate).tint(card.category.color)
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(card.category.title, systemImage: card.category.systemImage)
                        .font(.caption.weight(.bold)).foregroundStyle(card.category.color)
                    if card.spot != nil {
                        Text("SAVED").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.lagoon, in: Capsule())
                    }
                    Spacer()
                    Text(distanceText).font(.caption).foregroundStyle(.secondary)
                }
                Text(card.name).font(.title2.weight(.bold)).lineLimit(2)
                if !card.address.isEmpty { Text(card.address).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .overlay(alignment: .topLeading) {
            if drag.width > 40 { stamp("KEEP", Theme.lagoon) }
        }
        .overlay(alignment: .topTrailing) {
            if drag.width < -40 { stamp("SKIP", Theme.coral) }
        }
        .scaleEffect(isTop ? 1 : 0.95)
        .offset(x: drag.width, y: drag.height * 0.2)
        .rotationEffect(.degrees(Double(drag.width) / 20))
        .allowsHitTesting(isTop)
        .gesture(
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    if abs(value.translation.width) > 110 {
                        let keep = value.translation.width > 0
                        withAnimation(.easeOut(duration: 0.2)) { drag.width = keep ? 600 : -600 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDecide(keep) }
                    } else {
                        withAnimation(.spring) { drag = .zero }
                    }
                }
        )
    }

    private var distanceText: String {
        let m = AutoPlanner.distance(center, card.coordinate)
        return m < 1000 ? "\(Int(m)) m away" : String(format: "%.1f km away", m / 1000)
    }

    private func stamp(_ text: String, _ color: Color) -> some View {
        Text(text).font(.title.weight(.heavy)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(text == "KEEP" ? -12 : 12))
            .padding(24)
    }
}
