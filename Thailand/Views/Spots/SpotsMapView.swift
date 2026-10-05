import MapKit
import SwiftUI

/// My Map: every saved spot on a full-screen map with clustering, category / favorite / visited
/// filters and a city switcher. Uses MKMapView because SwiftUI's Map has no pin clustering.
struct SpotsMapView: View {
    @ObservedObject var trip: Trip
    let refreshTick: Int

    enum VisitFilter: String, CaseIterable { case all = "All", toGo = "To go", visited = "Visited" }

    @State private var category: SpotCategory?
    @State private var favoritesOnly = false
    @State private var visit: VisitFilter = .all
    @State private var showDrafts = false
    @State private var selected: Spot?
    @State private var focus: MapFocus?
    @State private var walkTarget: WalkTarget?
    @State private var detail: Spot?

    /// A request to move the camera (fit spots, a city, or a single spot).
    struct MapFocus: Equatable {
        let id = UUID()
        let coordinates: [CLLocationCoordinate2D]
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }

    private var spots: [Spot] {
        _ = refreshTick
        return trip.allSpots.filter { spot in
            spot.hasCoordinate
                && (showDrafts || !spot.isDraft)
                && (category == nil || spot.category == category)
                && (!favoritesOnly || spot.isFavorite)
                && (visit == .all || (visit == .visited) == spot.isVisited)
        }
    }

    private var cities: [(name: String, spots: [Spot])] {
        let saved = trip.confirmedSpots.filter(\.hasCoordinate)
        return Dictionary(grouping: saved) { ($0.city ?? "").isEmpty ? "Other" : $0.city! }
            .map { ($0.key, $0.value) }
            .sorted { $0.spots.count > $1.spots.count }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ClusteredSpotMap(spots: spots, selected: $selected, focus: focus)
                .ignoresSafeArea(edges: .bottom)

            filterBar
        }
        .safeAreaInset(edge: .bottom) {
            if let spot = selected { spotCard(spot) }
            else if spots.isEmpty { emptyHint }
        }
        .onAppear { if focus == nil { focus = MapFocus(coordinates: spots.compactMap(\.coordinate)) } }
        .navigationDestination(item: $detail) { SpotDetailView(spot: $0) }
        .fullScreenCover(item: $walkTarget) { target in
            WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
        }
    }

    // MARK: Filters

    private var filterBar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SpotCategory.allCases) { c in
                        CategoryChip(title: c.title, systemImage: c.systemImage, color: c.color, selected: category == c) {
                            category = category == c ? nil : c
                        }
                    }
                }
                .padding(.horizontal)
            }
            HStack(spacing: 6) {
                Menu {
                    Button("All spots (\(trip.confirmedSpots.filter(\.hasCoordinate).count))", systemImage: "globe.asia.australia") {
                        focus = MapFocus(coordinates: spots.compactMap(\.coordinate))
                    }
                    ForEach(cities, id: \.name) { city in
                        Button("\(city.name) (\(city.spots.count))") {
                            focus = MapFocus(coordinates: city.spots.compactMap(\.coordinate))
                        }
                    }
                } label: {
                    Label("Cities", systemImage: "building.2").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.cardBackground, in: Capsule())
                }
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(favoritesOnly ? .white : Theme.coral)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(favoritesOnly ? Theme.coral : Theme.cardBackground, in: Capsule())
                }
                .accessibilityLabel("Favorites only")
                Picker("Visited", selection: $visit) {
                    ForEach(VisitFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Button { showDrafts.toggle() } label: {
                    Image(systemName: showDrafts ? "tray.full.fill" : "tray")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(showDrafts ? Theme.mango.opacity(0.25) : Theme.cardBackground, in: Capsule())
                }
                .accessibilityLabel(showDrafts ? "Hide drafts" : "Show drafts")
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Cards

    private func spotCard(_ spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: spot.category.systemImage)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(spot.category.color, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(spot.displayName).font(.headline)
                        if spot.isDraft { Text("DRAFT").font(.caption2.weight(.heavy)).foregroundStyle(Theme.mango) }
                    }
                    Text(spot.address ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let tip = spot.sortedScoops.compactMap({ $0.recommendation }).first(where: { !$0.isEmpty }) {
                        Text("💬 \(tip)").font(.caption).lineLimit(2)
                    }
                }
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button { detail = spot } label: { Label("Details", systemImage: "info.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.mango)
                if let c = spot.coordinate {
                    Button { walkTarget = WalkTarget(name: spot.displayName, coordinate: c) } label: {
                        Label("Walk", systemImage: "figure.walk").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button { spot.isFavorite.toggle(); spot.touch() } label: {
                    Image(systemName: spot.isFavorite ? "heart.fill" : "heart")
                }
                .buttonStyle(.bordered).tint(Theme.coral)
                .accessibilityLabel(spot.isFavorite ? "Unfavorite" : "Favorite")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.horizontal)
    }

    private var emptyHint: some View {
        Text(trip.confirmedSpots.isEmpty
             ? "Saved spots appear here. Share a TikTok, Reel or Google Maps link to WanderHub, then confirm the drafts."
             : "No spots match these filters.")
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
            .padding(.horizontal)
    }
}

// MARK: - MKMapView with clustering

/// One map pin per spot. Pins share a clustering ID, so MapKit merges nearby pins into a count bubble.
final class SpotAnnotation: NSObject, MKAnnotation {
    let spot: Spot
    let coordinate: CLLocationCoordinate2D
    var title: String? { spot.displayName }
    var subtitle: String? { spot.category.title }

    init(spot: Spot, coordinate: CLLocationCoordinate2D) {
        self.spot = spot
        self.coordinate = coordinate
    }
}

struct ClusteredSpotMap: UIViewRepresentable {
    let spots: [Spot]
    @Binding var selected: Spot?
    let focus: SpotsMapView.MapFocus?
    /// When set, Apple's places (hotels, restaurants, sights…) show faintly and can be tapped to add.
    var onPickPlace: ((MKMapItem) -> Void)?
    /// When set, long-press anywhere drops a pin (for places Apple doesn't list, like an Airbnb).
    var onDropPin: ((CLLocationCoordinate2D) -> Void)?
    /// Photo pins of things to see (from Wikipedia) appear when you zoom into an area.
    var discover = false
    var onPickLandmark: ((Landmark) -> Void)?
    /// Researched must-sees, shown whenever discover is on.
    var topPicks: [TopPick] = []

    static let addablePlaces: [MKPointOfInterestCategory] = [
        .hotel, .restaurant, .cafe, .bakery, .foodMarket, .nightlife, .brewery, .winery, .museum, .park, .nationalPark,
        .beach, .landmark, .amusementPark, .aquarium, .zoo, .store, .spa, .marina, .theater, .musicVenue,
    ]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        if onPickPlace != nil {
            map.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.addablePlaces)
            map.selectableMapFeatures = [.pointsOfInterest]
        } else {
            map.pointOfInterestFilter = .excludingAll // your spots, not Apple's
        }
        if onDropPin != nil {
            let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
            press.minimumPressDuration = 0.5
            map.addGestureRecognizer(press)
        }
        map.register(SpotMarkerView.self, forAnnotationViewWithReuseIdentifier: SpotMarkerView.id)
        map.register(SpotPhotoAnnotationView.self, forAnnotationViewWithReuseIdentifier: SpotPhotoAnnotationView.id)
        map.register(DiscoverAnnotationView.self, forAnnotationViewWithReuseIdentifier: DiscoverAnnotationView.id)
        map.register(SpotClusterView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        // Sync annotations (cheap even for hundreds of spots).
        let current = map.annotations.compactMap { $0 as? SpotAnnotation }
        let wanted = Set(spots.map(\.objectID))
        let stale = current.filter { annotation in
            guard wanted.contains(annotation.spot.objectID), let c = annotation.spot.coordinate else { return true }
            return c.latitude != annotation.coordinate.latitude || c.longitude != annotation.coordinate.longitude
        }
        map.removeAnnotations(stale)
        let have = Set(current.filter { !stale.contains($0) }.map(\.spot.objectID))
        map.addAnnotations(spots.filter { !have.contains($0.objectID) }.compactMap { spot in
            spot.coordinate.map { SpotAnnotation(spot: spot, coordinate: $0) }
        })

        if let focus, focus != context.coordinator.lastFocus {
            context.coordinator.lastFocus = focus
            fit(map, focus.coordinates)
        }
        if selected == nil { map.selectedAnnotations.filter { $0 is SpotAnnotation }.forEach { map.deselectAnnotation($0, animated: true) } }
        if !discover {
            map.removeAnnotations(map.annotations.filter { $0 is DiscoverAnnotation })
        } else {
            // Top picks you haven't saved yet.
            let shownTop = Set(map.annotations.compactMap { ($0 as? DiscoverAnnotation).flatMap { $0.isTopPick ? $0.landmark.id : nil } })
            let unsaved = topPicks.filter { pick in
                guard let c = pick.coordinate else { return false }
                return !spots.contains { s in s.coordinate.map { AutoPlanner.distance($0, c) < 120 } ?? false
                    && NameMatch.similarity(s.displayName, pick.name) >= 0.4 }
            }
            let wanted = Set(unsaved.compactMap { $0.landmark?.id })
            map.removeAnnotations(map.annotations.filter { a in
                guard let d = a as? DiscoverAnnotation, d.isTopPick else { return false }
                return !wanted.contains(d.landmark.id)
            })
            map.addAnnotations(unsaved.compactMap { $0.landmark }.filter { !shownTop.contains($0.id) }
                .map { DiscoverAnnotation($0, isTopPick: true) })
            if !map.annotations.contains(where: { ($0 as? DiscoverAnnotation)?.isTopPick == false }) {
                context.coordinator.loadDiscover(map)
            }
        }
    }

    private func fit(_ map: MKMapView, _ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            map.setRegion(MKCoordinateRegion(center: TravelArea.all[0].coordinate, latitudinalMeters: 15_000, longitudinalMeters: 15_000), animated: false)
            return
        }
        if coordinates.count == 1 {
            map.setRegion(MKCoordinateRegion(center: coordinates[0], latitudinalMeters: 1_500, longitudinalMeters: 1_500), animated: true)
            return
        }
        let rect = coordinates.reduce(MKMapRect.null) { r, c in
            r.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 1, height: 1)))
        }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 140, left: 40, bottom: 220, right: 40), animated: true)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredSpotMap
        var lastFocus: SpotsMapView.MapFocus?
        @MainActor private lazy var discoverLoader = DiscoverLoader()

        @MainActor func loadDiscover(_ map: MKMapView) {
            guard parent.discover else { return }
            discoverLoader.regionChanged(map, savedSpots: parent.spots) { [weak map] landmarks in
                guard let map, self.parent.discover else { return }
                let shown = Set(map.annotations.compactMap { ($0 as? DiscoverAnnotation)?.landmark.id })
                // Skip Wikipedia pins that duplicate a top pick.
                let tops = map.annotations.compactMap { ($0 as? DiscoverAnnotation).flatMap { $0.isTopPick ? $0.landmark : nil } }
                map.addAnnotations(landmarks.filter { l in
                    !shown.contains(l.id) && !tops.contains { AutoPlanner.distance($0.coordinate, l.coordinate) < 150 }
                }.map { DiscoverAnnotation($0) })
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            MainActor.assumeIsolated { loadDiscover(mapView) }
        }

        init(_ parent: ClusteredSpotMap) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is DiscoverAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: DiscoverAnnotationView.id, for: annotation)
            }
            guard annotation is SpotAnnotation else { return nil } // user dot + clusters use defaults/registered
            return mapView.dequeueReusableAnnotationView(withIdentifier: SpotPhotoAnnotationView.id, for: annotation)
        }

        @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onDropPin?(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let discover = annotation as? DiscoverAnnotation {
                parent.onPickLandmark?(discover.landmark)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { mapView.deselectAnnotation(discover, animated: true) }
                return
            }
            if let feature = annotation as? MKMapFeatureAnnotation {
                // One of Apple's places: look it up and offer to add it.
                mapView.deselectAnnotation(feature, animated: false)
                Task { @MainActor in
                    if let item = try? await MKMapItemRequest(mapFeatureAnnotation: feature).mapItem {
                        self.parent.onPickPlace?(item)
                    }
                }
                return
            }
            if let cluster = annotation as? MKClusterAnnotation {
                // Zoom into a cluster instead of selecting it.
                let rect = cluster.memberAnnotations.reduce(MKMapRect.null) { r, a in
                    r.union(MKMapRect(origin: MKMapPoint(a.coordinate), size: MKMapSize(width: 1, height: 1)))
                }
                mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 160, left: 60, bottom: 240, right: 60), animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
            } else if let spot = (annotation as? SpotAnnotation)?.spot {
                parent.selected = spot
            }
        }
    }
}

/// Category-colored marker with the category glyph.
final class SpotMarkerView: MKMarkerAnnotationView {
    static let id = "spot"

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "spots"
        collisionMode = .circle
        displayPriority = .defaultHigh
        configure()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        guard let spot = (annotation as? SpotAnnotation)?.spot else { return }
        clusteringIdentifier = "spots"
        markerTintColor = UIColor(spot.category.color).withAlphaComponent(spot.isDraft ? 0.55 : 1)
        glyphImage = UIImage(systemName: spot.isVisited ? "checkmark" : spot.category.systemImage)
        titleVisibility = .adaptive
        subtitleVisibility = .hidden
    }
}

/// Cluster: a photo from one of its spots with a count badge (zoom in to split it).
final class SpotClusterView: MKAnnotationView {
    private static let size: CGFloat = 54
    private let photo = UIImageView()
    private let ring = UIView()
    private let count = UILabel()
    private var loadTask: Task<Void, Never>?

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let s = Self.size
        frame = CGRect(x: 0, y: 0, width: s + 10, height: s + 10)
        displayPriority = .required
        collisionMode = .circle

        ring.frame = CGRect(x: 5, y: 5, width: s, height: s)
        ring.layer.cornerRadius = s / 2
        ring.backgroundColor = .white
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.28
        ring.layer.shadowRadius = 5
        ring.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(ring)

        photo.frame = ring.frame.insetBy(dx: 3, dy: 3)
        photo.layer.cornerRadius = photo.frame.width / 2
        photo.clipsToBounds = true
        photo.contentMode = .scaleAspectFill
        photo.backgroundColor = UIColor(Theme.ink).withAlphaComponent(0.2)
        addSubview(photo)

        count.font = .systemFont(ofSize: 12, weight: .heavy)
        count.textColor = .white
        count.textAlignment = .center
        count.backgroundColor = UIColor(Theme.ink)
        count.layer.cornerRadius = 11
        count.layer.borderColor = UIColor.white.cgColor
        count.layer.borderWidth = 2
        count.clipsToBounds = true
        addSubview(count)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        photo.image = nil
    }

    private func configure() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let n = cluster.memberAnnotations.count
        count.text = n > 99 ? "99+" : "\(n)"
        let width = max(22, CGFloat(count.text!.count) * 8 + 12)
        count.frame = CGRect(x: Self.size + 6 - width, y: 0, width: width, height: 22)
        accessibilityLabel = "\(n) spots"

        let spots = cluster.memberAnnotations.compactMap { ($0 as? SpotAnnotation)?.spot }
        photo.image = UIImage(systemName: "mappin.and.ellipse")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
            .withTintColor(UIColor(Theme.ink), renderingMode: .alwaysOriginal)
        photo.contentMode = .center
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            // First spot with a photo (favorites first) represents the cluster.
            for spot in spots.sorted(by: { $0.isFavorite && !$1.isFavorite }).prefix(6) {
                guard !Task.isCancelled else { return }
                if let url = await SpotPhoto.url(for: spot), let image = await ImageCache.image(at: url) {
                    guard let self, self.annotation === cluster else { return }
                    UIView.transition(with: self.photo, duration: 0.25, options: .transitionCrossDissolve) {
                        self.photo.contentMode = .scaleAspectFill
                        self.photo.image = image
                    }
                    return
                }
            }
        }
    }
}
