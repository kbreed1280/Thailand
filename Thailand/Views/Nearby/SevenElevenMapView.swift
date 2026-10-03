import MapKit
import SwiftUI

/// Full-screen map of every 7-Eleven in view (OpenStreetMap), with walking directions.
struct SevenElevenMapView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var location = LocationService.shared

    @State private var position: MapCameraPosition = .userLocation(
        fallback: .region(MKCoordinateRegion(center: WeatherPlace.cities[0].location.coordinate,
                                             latitudinalMeters: 2_000, longitudinalMeters: 2_000)))
    @State private var region: MKCoordinateRegion?
    @State private var stores: [ConvenienceStore] = []
    @State private var zoomedOut = false
    @State private var loading = false
    @State private var selected: ConvenienceStore?
    @State private var walkTarget: WalkTarget?
    @State private var here: CLLocation?

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selected) {
                UserAnnotation()
                ForEach(stores) { store in
                    Annotation(store.name, coordinate: store.coordinate, anchor: .bottom) {
                        SevenElevenPin(selected: store == selected)
                    }
                    .tag(store)
                    .annotationTitles(.hidden)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                Task { await load(context.region) }
            }
            .overlay(alignment: .top) { statusBanner }
            .safeAreaInset(edge: .bottom) {
                if let selected { storeCard(selected) }
            }
            .navigationTitle("7-Elevens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let c = region?.center ?? here?.coordinate { SevenElevenService.openInGoogleMaps(near: c) }
                    } label: {
                        Label("Open in Google Maps", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .task { here = await location.currentLocation() }
            .fullScreenCover(item: $walkTarget) { target in
                WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
            }
        }
    }

    private func load(_ region: MKCoordinateRegion) async {
        loading = true
        defer { loading = false }
        let result = await SevenElevenService.stores(in: region)
        zoomedOut = result.zoomedOutTooFar
        if !result.zoomedOutTooFar {
            // Keep the closest few hundred to the center so the map stays fast.
            let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            stores = Array(result.stores.sorted { $0.location.distance(from: center) < $1.location.distance(from: center) }.prefix(300))
        }
    }

    @ViewBuilder private var statusBanner: some View {
        Group {
            if zoomedOut {
                Label("Zoom in to see 7-Elevens", systemImage: "plus.magnifyingglass")
            } else if loading && stores.isEmpty {
                Label("Finding 7-Elevens…", systemImage: "hourglass")
            } else if !loading && stores.isEmpty && region != nil {
                Label("No 7-Elevens mapped here", systemImage: "mappin.slash")
            } else if !stores.isEmpty {
                Label("\(stores.count) in view", systemImage: "storefront.fill")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 8)
    }

    private func storeCard(_ store: ConvenienceStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SevenElevenPin(selected: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.branch.map { "7-Eleven · \($0)" } ?? store.name).font(.headline)
                    HStack(spacing: 6) {
                        if let here {
                            let meters = store.location.distance(from: here)
                            Text("\(Distance.text(meters)) · \(Distance.walkingTime(meters)) walk")
                        }
                        if store.isOpen24h { Text("· Open 24h").foregroundStyle(Theme.lagoon) }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    walkTarget = WalkTarget(name: store.name, coordinate: store.coordinate)
                } label: { Label("Walk There", systemImage: "figure.walk").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Theme.mango)
                Button {
                    ExternalApps.openGoogleMaps(stops: [store.coordinate])
                } label: { Label("Google Maps", systemImage: "map").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.horizontal)
    }
}

/// The green/orange 7-Eleven-style pin.
struct SevenElevenPin: View {
    var selected = false

    var body: some View {
        Text("7")
            .font(.system(size: selected ? 15 : 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: selected ? 30 : 20, height: selected ? 30 : 20)
            .background(
                LinearGradient(colors: [Color(hex: "#008163"), Color(hex: "#008163"), Color(hex: "#EE2526"), Color(hex: "#F47920")],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.white, lineWidth: 1.5))
            .shadow(radius: 1.5)
            .accessibilityLabel("7-Eleven")
    }
}

enum Distance {
    /// "120 m" / "1.4 km"
    static func text(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int((meters / 10).rounded() * 10)) m" : String(format: "%.1f km", meters / 1_000)
    }

    /// ~4.5 km/h walking pace.
    static func walkingTime(_ meters: Double) -> String {
        let minutes = max(1, Int((meters / 75).rounded()))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// "Nearest 7-Eleven: 120 m" row for the Nearby tab.
struct NearestSevenElevenRow: View {
    let here: CLLocation
    let onWalk: (WalkTarget) -> Void
    let onShowMap: () -> Void

    @State private var nearest: ConvenienceStore?
    @State private var looked = false

    var body: some View {
        HStack(spacing: 12) {
            SevenElevenPin(selected: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nearest 7-Eleven").font(.subheadline.weight(.semibold))
                if let nearest {
                    let meters = nearest.location.distance(from: here)
                    Text("\(Distance.text(meters)) · \(Distance.walkingTime(meters)) walk")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(looked ? "None found nearby" : "Looking…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let nearest {
                Button("Walk") { onWalk(WalkTarget(name: nearest.name, coordinate: nearest.coordinate)) }
                    .buttonStyle(.borderedProminent).tint(Theme.mango).controlSize(.small)
            }
            Button("Map", action: onShowMap).buttonStyle(.bordered).controlSize(.small)
        }
        .card(padding: 12)
        .task(id: "\(Int(here.coordinate.latitude * 500)),\(Int(here.coordinate.longitude * 500))") {
            nearest = await SevenElevenService.nearest(to: here, limit: 1).first
            looked = true
        }
    }
}
