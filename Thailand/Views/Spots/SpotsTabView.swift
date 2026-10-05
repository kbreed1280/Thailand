import CoreData
import MapKit
import PhotosUI
import SwiftUI

/// Soft, paper-and-ink look for the Spots tab (light and dark).
enum PlotStyle {
    static let ink = Theme.ink
    static let paper = Theme.background
    static let card = Theme.cardBackground
    static let chip = Theme.insetBackground
    static let line = Theme.hairline
}

/// The Spots tab: every saved spot on a full-screen map, category pills on top, and a
/// pull-up sheet with search (or paste a link), filters and photo cards.
struct SpotsTabView: View {
    var body: some View {
        CurrentTripReader { trip in
            if let trip {
                SpotsHomeView(trip: trip)
            } else {
                ContentUnavailableView("No trip yet", systemImage: "suitcase",
                                       description: Text("Create a trip on the Trip tab, then save spots from TikTok, Instagram, YouTube, Google Maps or any web page."))
            }
        }
    }
}

struct SpotsHomeView: View {
    @ObservedObject var trip: Trip
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var pipeline = ImportPipeline.shared
    @ObservedObject private var location = LocationService.shared

    enum Detent: CaseIterable { case peek, half, full }

    @State private var category: SpotCategory?
    @State private var notVisited = false
    @State private var favorites = false
    @State private var search = ""
    @State private var selected: Spot?
    @State private var focus: SpotsMapView.MapFocus?
    @State private var detent: Detent = .half
    @State private var dragOffset: CGFloat = 0
    @State private var path: [Spot] = []
    @State private var refreshTick = 0

    @State private var showingInbox = false
    @State private var showingCollections = false
    @State private var showingSearchPlace = false
    @State private var showingAutoPlan = false
    @State private var showingSidequest = false
    @State private var showingTrending = false
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var showingScreenshots = false
    @State private var placeToAdd: PlaceToAdd?
    @State private var landmark: Landmark?
    @AppStorage("mapDiscover") private var discover = true
    @AppStorage(DiscoverKind.storageKey) private var discoverKindsRaw = DiscoverKind.encode(DiscoverKind.defaultSelection)
    private var discoverKinds: Set<DiscoverKind> { DiscoverKind.decode(discoverKindsRaw) }
    /// Apple's own map places: only the tapped category (nil = all the usual kinds).
    private var applePlaces: [MKPointOfInterestCategory]? {
        guard let category else { return nil }
        return DiscoverKind.forCategory(category)?.poiCategories ?? []
    }

    /// What the map layer shows: your picks, or only the tapped category (e.g. Brew → coffee shops only).
    private var visibleKinds: Set<DiscoverKind> {
        guard let category else { return discoverKinds }
        return DiscoverKind.forCategory(category).map { [$0] } ?? []
    }
    @State private var topPicks: [TopPick] = TopPicks.bangkok.filter { $0.coordinate != nil }
    @State private var addedTopPicks: Int?
    @State private var walkTarget: WalkTarget?

    /// False when this trip was shared with you as view-only.
    private var canEdit: Bool { PersistenceController.shared.canEdit(trip) }

    private var waiting: Int { _ = refreshTick; return SharedInbox.load().count + trip.draftSpots.count }

    private var spots: [Spot] {
        _ = refreshTick
        let query = search.trimmingCharacters(in: .whitespaces)
        return trip.confirmedSpots.filter { spot in
            (category == nil || spot.category == category)
                && (!notVisited || !spot.isVisited)
                && (!favorites || spot.isFavorite)
                && (query.isEmpty || SharedInbox.firstURL(in: query) != nil
                    || [spot.displayName, spot.city ?? "", spot.address ?? ""].contains { $0.localizedCaseInsensitiveContains(query) })
        }
        .sorted { distance(to: $0) < distance(to: $1) }
    }

    private var pastedURL: URL? { SharedInbox.firstURL(in: search) }

    var body: some View {
        withSheets(core)
    }

    private var mapLayer: some View {
        ClusteredSpotMap(spots: spots.filter(\.hasCoordinate), selected: $selected, focus: focus,
                         onPickPlace: canEdit ? { item in placeToAdd = PlaceToAdd(mapItem: item, coordinate: item.placemark.coordinate) } : nil,
                         onDropPin: canEdit ? { c in placeToAdd = PlaceToAdd(mapItem: nil, coordinate: c) } : nil,
                         discover: discover && !visibleKinds.isEmpty,
                         discoverKinds: visibleKinds,
                         onPickLandmark: { landmark = $0 },
                         applePlaces: applePlaces,
                         topPicks: topPicks)
    }

    private var core: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    mapLayer
                        .ignoresSafeArea()

                    topBar

                    sheet(height: geo.size.height)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Spot.self) { SpotDetailView(spot: $0) }
            .fontDesign(.rounded)
        }
        .onAppear {
            guard focus == nil else { return }
            #if DEBUG
            // Debug-only: `-debugFocusBangkok YES` opens the map zoomed into central Bangkok.
            // Debug-only: `-debugCategory brew` starts with a category pill selected.
            if let raw = UserDefaults.standard.string(forKey: "debugCategory") { category = SpotCategory(rawValue: raw) }
            if UserDefaults.standard.bool(forKey: "debugFocusSilom") {
                focus = .init(coordinates: [.init(latitude: 13.722, longitude: 100.524), .init(latitude: 13.735, longitude: 100.540)])
                return
            }
            if UserDefaults.standard.bool(forKey: "debugFocusBangkok") {
                focus = .init(coordinates: [.init(latitude: 13.70, longitude: 100.47), .init(latitude: 13.77, longitude: 100.56)])
                return
            }
            #endif
            focus = .init(coordinates: trip.confirmedSpots.compactMap(\.coordinate))
        }
        .task {
            location.requestPermission()
            guard canEdit else { return } // imports go into trips you can edit
            await pipeline.processInbox(into: trip, context: context)
            refreshTick &+= 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await pipeline.processInbox(into: trip, context: context); refreshTick &+= 1 } }
        }
        .onChange(of: selected) { _, spot in
            guard let spot else { return }
            withAnimation(.snappy) { detent = .peek }
            if let c = spot.coordinate { focus = .init(coordinates: [c]) }
        }
        .onChange(of: screenshotItems) { _, items in Task { await importScreenshots(items) } }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
            refreshTick &+= 1
        }
    }

    private func landmarkSheet(_ l: Landmark) -> some View {
        let category: SpotCategory = topPicks.first(where: { $0.landmark?.id == l.id })?.spotCategory ?? .explore
        return LandmarkDetailSheet(landmark: l, userLocation: location.lastLocation, onWalk: { target in
            landmark = nil
            walkTarget = target
        }, spotCategory: category)
    }

    private func withSheets<V: View>(_ view: V) -> some View {
        view
        .sheet(isPresented: $showingInbox) { SpotsView(trip: trip) }
        .sheet(item: $landmark) { landmarkSheet($0) }
        .task { topPicks = await TopPicks.bangkokLocated() }
        .fullScreenCover(item: $walkTarget) { target in
            WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
        }
        .alert("Bangkok Top Picks added", isPresented: Binding(get: { addedTopPicks != nil }, set: { if !$0 { addedTopPicks = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(addedTopPicks ?? 0) places are in your Spots and in the \"Bangkok Top Picks\" list (Collections).")
        }
        .sheet(item: $placeToAdd) { place in
            AddPlaceSheet(place: place, trip: trip) { spot in selected = spot }
        }
        .sheet(isPresented: $showingCollections) { SpotCollectionsHome(trip: trip) }
        .sheet(isPresented: $showingSearchPlace) {
            SpotPlaceSearchSheet(title: "Add a spot", cityHint: nil) { addManual($0) }
        }
        .sheet(isPresented: $showingAutoPlan) { AutoPlanView(trip: trip) }
        .sheet(isPresented: $showingTrending) { TrendingNearbyView(trip: trip) }
        .fullScreenCover(isPresented: $showingSidequest) { SidequestView(trip: trip) }
        .photosPicker(isPresented: $showingScreenshots, selection: $screenshotItems, maxSelectionCount: 10, matching: .screenshots)
    }

    // MARK: Top bar: category pills + buttons

    private var topBar: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 10) {
                Button { showingCollections = true } label: {
                    Image(systemName: "square.stack.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PlotStyle.ink)
                        .frame(width: 48, height: 48)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Collections")
                Spacer()
                if !canEdit {
                    Label("View only", systemImage: "eye.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlotStyle.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                if canEdit {
                Button { showingInbox = true } label: {
                    Image(systemName: "tray.full.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PlotStyle.ink)
                        .frame(width: 48, height: 48)
                        .background(.regularMaterial, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if waiting > 0 {
                                Text("\(waiting)")
                                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.coral, in: Capsule())
                            }
                        }
                }
                .accessibilityLabel(waiting > 0 ? "Drafts, \(waiting) new" : "Drafts")
                }
                Menu {
                    Section("Show on the map when zoomed in") {
                        ForEach(DiscoverKind.allCases) { kind in
                            Toggle(isOn: Binding(
                                get: { discover && discoverKinds.contains(kind) },
                                set: { on in
                                    var kinds = discoverKinds
                                    if on { kinds.insert(kind); discover = true } else { kinds.remove(kind) }
                                    discoverKindsRaw = DiscoverKind.encode(kinds)
                                })) {
                                Label(kind.title, systemImage: kind.spotCategory.systemImage)
                            }
                        }
                    }
                    Button(discover ? "Hide all" : "Show", systemImage: discover ? "eye.slash" : "eye") { discover.toggle() }
                } label: {
                    let on = discover && !discoverKinds.isEmpty
                    Image(systemName: on ? "photo.stack.fill" : "photo.stack")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(on ? .white : PlotStyle.ink)
                        .frame(width: 48, height: 48)
                        .background(on ? AnyShapeStyle(Theme.mango) : AnyShapeStyle(.regularMaterial), in: Circle())
                }
                .accessibilityLabel("Places shown on the map")
                if canEdit { addMenu }
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        pill("All", icon: nil, color: PlotStyle.ink, selected: category == nil) { category = nil }
                            .id("all")
                        ForEach(SpotCategory.allCases) { c in
                            pill(c.title, icon: c.systemImage, color: c.color, selected: category == c) {
                                category = category == c ? nil : c
                            }
                            .id(c.rawValue)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: category, initial: true) { _, c in
                    withAnimation(.snappy) { proxy.scrollTo(c?.rawValue ?? "all", anchor: .center) }
                }
            }
        }
        .padding(.top, 4)
    }

    private func pill(_ title: String, icon: String?, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).foregroundStyle(selected ? .white : color) }
                Text(LocalizedStringKey(title))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(selected ? AnyShapeStyle(PlotStyle.ink) : AnyShapeStyle(.regularMaterial), in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var addMenu: some View {
        Menu {
            Button("Search for a place", systemImage: "magnifyingglass") { showingSearchPlace = true }
            Button("Add screenshots", systemImage: "text.viewfinder") { showingScreenshots = true }
            Divider()
            Button("Auto-plan days", systemImage: "wand.and.sparkles") { showingAutoPlan = true }
            Button("Sidequest", systemImage: "dice") { showingSidequest = true }
            Button("Trending nearby", systemImage: "flame") { showingTrending = true }
            Divider()
            Button("Add Bangkok Top Picks (\(TopPicks.bangkok.count))", systemImage: "star.circle") {
                Task {
                    let picks = await TopPicks.bangkokLocated()
                    topPicks = picks
                    let list = TopPicks.saveAll(picks, to: trip, context: context)
                    addedTopPicks = list.spots.count
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(PlotStyle.ink, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel("Add")
    }

    // MARK: Pull-up sheet

    private func height(_ d: Detent, in total: CGFloat) -> CGFloat {
        switch d {
        case .peek: 150
        case .half: total * 0.46
        case .full: total * 0.86
        }
    }

    private func sheet(height total: CGFloat) -> some View {
        let base = height(detent, in: total)
        let current = min(max(base - dragOffset, 110), total * 0.92)
        return VStack(spacing: 0) {
            VStack(spacing: 12) {
                Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 8)
                searchField
                if detent != .peek || selected != nil { filterRow }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation.height }
                    .onEnded { value in
                        let target = base - value.predictedEndTranslation.height
                        let next = Detent.allCases.min { abs(height($0, in: total) - target) < abs(height($1, in: total) - target) } ?? .half
                        withAnimation(.snappy) { detent = next; dragOffset = 0 }
                    }
            )

            if let spot = selected, detent == .peek {
                SpotCard(spot: spot, distance: distanceText(spot)) { path.append(spot) }
                    .padding(.horizontal)
                    .overlay(alignment: .topTrailing) {
                        Button { selected = nil } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 24).padding(.top, 6)
                    }
                Spacer(minLength: 0)
            } else {
                list
            }
        }
        .frame(height: selected != nil && detent == .peek ? max(current, 260) : current)
        .frame(maxWidth: .infinity)
        .background(PlotStyle.paper, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search places or cities, or paste a link", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onTapGesture { withAnimation(.snappy) { detent = .full } }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in importLink(text) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .tint(PlotStyle.ink)
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
        .frame(minHeight: 50)
        .background(PlotStyle.card, in: Capsule())
        .overlay(Capsule().stroke(PlotStyle.line))
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Everywhere", systemImage: "globe.asia.australia") {
                        focus = .init(coordinates: trip.confirmedSpots.compactMap(\.coordinate))
                    }
                    ForEach(cities, id: \.name) { city in
                        Button("\(city.name) (\(city.spots.count))") { focus = .init(coordinates: city.spots.compactMap(\.coordinate)) }
                    }
                } label: {
                    filterChip("Cities", icon: "building.2", on: false)
                }
                Button { notVisited.toggle() } label: { filterChip("Not visited", icon: notVisited ? "circle.inset.filled" : "circle.dashed", on: notVisited) }
                Button { favorites.toggle() } label: { filterChip("Favorite", icon: favorites ? "star.fill" : "star", on: favorites) }
            }
        }
        .buttonStyle(.plain)
    }

    private func filterChip(_ title: String, icon: String, on: Bool) -> some View {
        Label(LocalizedStringKey(title), systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(on ? .white : .primary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(on ? PlotStyle.ink : PlotStyle.card, in: Capsule())
            .overlay(Capsule().stroke(on ? .clear : PlotStyle.line))
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let url = pastedURL {
                    Button { importLink(url.absoluteString) } label: {
                        Label("Import this link", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(PlotStyle.ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                if waiting > 0 {
                    Button { showingInbox = true } label: {
                        HStack {
                            Image(systemName: "tray.full.fill").foregroundStyle(Theme.mango)
                            Text("\(waiting) new to review").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Theme.mango.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(spots) { spot in
                    SpotCard(spot: spot, distance: distanceText(spot)) { path.append(spot) }
                }
                if spots.isEmpty, pastedURL == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse").font(.largeTitle).foregroundStyle(PlotStyle.ink)
                        Text(trip.confirmedSpots.isEmpty ? "No spots yet" : "No spots match").font(.headline)
                        Text(trip.confirmedSpots.isEmpty
                             ? "Tap any hotel, restaurant or sight on the map to add it, or long-press to drop a pin. You can also share posts from TikTok, Instagram, YouTube or Google Maps to WanderHub."
                             : "Try another category or filter.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 24).padding(.horizontal)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Helpers

    private var cities: [(name: String, spots: [Spot])] {
        Dictionary(grouping: trip.confirmedSpots.filter(\.hasCoordinate)) { ($0.city ?? "").isEmpty ? "Other" : $0.city! }
            .map { ($0.key, $0.value) }
            .sorted { $0.spots.count > $1.spots.count }
    }

    private func distance(to spot: Spot) -> CLLocationDistance {
        guard let here = location.lastLocation, let c = spot.coordinate else { return .greatestFiniteMagnitude }
        return here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    private func distanceText(_ spot: Spot) -> String? {
        let d = distance(to: spot)
        guard d < .greatestFiniteMagnitude else { return nil }
        let m = Measurement(value: d, unit: UnitLength.meters)
        return m.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    private func importLink(_ text: String) {
        let url = SharedInbox.firstURL(in: text)
        pipeline.addSource(url: url, text: url == nil ? text : nil, to: trip, context: context)
        search = ""
        showingInbox = true
        Task { await pipeline.importPending(in: trip, context: context) }
    }

    private func importScreenshots(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            let text = await ScreenshotText.recognize(image)
            if !text.isEmpty { pipeline.addSource(url: nil, text: text, to: trip, context: context) }
        }
        screenshotItems = []
        showingInbox = true
        await pipeline.importPending(in: trip, context: context)
    }

    private func addManual(_ item: MKMapItem) {
        let spot = Spot(context: context)
        spot.placeInSameStore(as: trip)
        spot.uuid = UUID()
        spot.status = .confirmed
        spot.addedBy = AppSettings.displayName
        spot.createdAt = .now
        spot.trip = trip
        spot.apply(item)
        ItineraryStore(context: context).save()
        selected = spot
    }
}

// MARK: - Spot card (photo, city, name, category, distance)

struct SpotCard: View {
    @ObservedObject var spot: Spot
    let distance: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                SpotThumbnail(spot: spot)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("🇹🇭 \(spot.city?.isEmpty == false ? spot.city! : "Thailand")")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text(spot.displayName)
                        .font(.title3.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if spot.isVisited {
                        Label("Visited", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.lagoon)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Image(systemName: spot.category.systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PlotStyle.ink)
                        .frame(width: 44, height: 44)
                        .background(PlotStyle.chip, in: Circle())
                    if let distance { Text(distance).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            .padding(12)
            .background(PlotStyle.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// A spot's picture: the post it came from (when the post is about just this place), a
/// Wikipedia photo for landmarks, or a small map of the spot.
struct SpotThumbnail: View {
    let spot: Spot
    @State private var photo: URL?

    var body: some View {
        Group {
            if let photo {
                AsyncImage(url: photo) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { MapThumbnail(spot: spot) }
                }
            } else {
                MapThumbnail(spot: spot)
            }
        }
        .task(id: spot.objectID) { photo = await SpotPhoto.url(for: spot) }
    }
}

/// Map snapshot around a spot, cached so scrolling stays smooth.
struct MapThumbnail: View {
    let spot: Spot
    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                spot.category.color.opacity(0.18)
            }
            Image(systemName: spot.category.systemImage)
                .font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(spot.category.color, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
        .task(id: spot.objectID) { await load() }
    }

    private func load() async {
        guard let c = spot.coordinate else { return }
        let key = String(format: "%.5f,%.5f", c.latitude, c.longitude) as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: c, latitudinalMeters: 450, longitudinalMeters: 450)
        options.size = CGSize(width: 180, height: 180)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }
        Self.cache.setObject(snapshot.image, forKey: key)
        image = snapshot.image
    }
}
