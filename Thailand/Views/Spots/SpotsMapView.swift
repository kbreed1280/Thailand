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
        if selected == nil { map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) } }
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

        init(_ parent: ClusteredSpotMap) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is SpotAnnotation else { return nil } // user dot + clusters use defaults/registered
            return mapView.dequeueReusableAnnotationView(withIdentifier: SpotMarkerView.id, for: annotation)
        }

        @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onDropPin?(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
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

/// Cluster bubble showing how many spots it holds.
final class SpotClusterView: MKMarkerAnnotationView {
    override var annotation: MKAnnotation? {
        didSet {
            guard let cluster = annotation as? MKClusterAnnotation else { return }
            glyphText = cluster.memberAnnotations.count > 99 ? "99+" : "\(cluster.memberAnnotations.count)"
            markerTintColor = UIColor(Theme.mango)
            displayPriority = .required
        }
    }
}
