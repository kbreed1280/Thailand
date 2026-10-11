import MapKit
import SwiftUI

/// A shareable summary of a trip: the route on a map, the numbers, and the highlights.
struct TripRecapView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var mapImage: UIImage?
    @State private var shareImage: Image?

    private var stops: [Item] { trip.sortedDays.flatMap(\.sortedItems) }
    private var points: [CLLocationCoordinate2D] {
        (stops.compactMap(\.coordinate) + trip.sortedVisits.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
    }

    /// Walking distance along each day's stops, in meters.
    private var routeMeters: Double {
        trip.sortedDays.reduce(0) { total, day in
            let coords = day.sortedItems.compactMap(\.coordinate)
            return total + zip(coords, coords.dropFirst()).reduce(0) { $0 + AutoPlanner.distance($1.0, $1.1) }
        }
    }

    private var spent: Double { trip.sortedExpenses.reduce(0) { $0 + $1.amountTHB } }
    private var photoCount: Int { stops.reduce(0) { $0 + $1.sortedPhotos.count } }

    /// Visited places first, then the planned stops, without repeats.
    private var highlights: [String] {
        var seen = Set<String>()
        return (trip.sortedVisits.compactMap(\.placeName) + stops.map(\.displayTitle))
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                card
                    .padding()
                if let shareImage {
                    ShareLink(item: shareImage, preview: SharePreview("\(trip.displayName) recap", image: shareImage)) {
                        Label("Share recap", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Theme.ink, in: Capsule())
                    }
                    .padding(.horizontal)
                }
            }
            .background(Theme.background)
            .navigationTitle("Trip Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                mapImage = await snapshot()
                render()
            }
        }
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(CurrencyContext.flag(trip.country)) TRIP RECAP").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.8))
                Text(trip.displayName).font(.largeTitle.bold()).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                if let start = trip.startDate, let end = trip.endDate {
                    Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                }
            }

            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable().scaledToFill()
                    .frame(height: 190).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                stat("\(trip.sortedDays.count)", "days")
                stat("\(stops.count)", "stops")
                stat(DistanceText.distance(routeMeters), "explored")
                stat("\(trip.confirmedSpots.count)", "spots saved")
                stat("\(photoCount)", "photos")
                stat(spent > 0 ? CurrencyMath.format(spent, .local) : "–", "spent")
            }

            if !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HIGHLIGHTS").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.8))
                    ForEach(highlights, id: \.self) { name in
                        Label(name, systemImage: "mappin.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }
                }
            }

            HStack {
                Spacer()
                Text("Planned with Trip Butler").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(
            LinearGradient(colors: [Color(hex: "#1D4ED8"), Color(hex: "#0E7490"), Color(hex: "#F97316")],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Rendering

    private func render() {
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .light))
        renderer.scale = displayScale
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }

    /// A map of everywhere the trip went, with a dot for each stop.
    private func snapshot() async -> UIImage? {
        let coords = points
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.4),
                                    longitudeDelta: max(0.02, (lons.max()! - lons.min()!) * 1.4))
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 640, height: 380)
        options.pointOfInterestFilter = .excludingAll
        guard let shot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        return UIGraphicsImageRenderer(size: options.size).image { _ in
            shot.image.draw(at: .zero)
            for c in coords {
                let p = shot.point(for: c)
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)).fill()
                UIColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill()
            }
        }
    }
}
