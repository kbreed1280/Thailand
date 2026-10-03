import SwiftUI
import MapKit

/// Get ready for no signal: save this trip's routes, day maps and Thai addresses,
/// and download each city in Apple Maps and Google Maps.
struct OfflinePackView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var store = OfflinePackStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var viewingMap: OfflineDayMap?
    @State private var showContent: ShowModeContent?
    @State private var confirmingDelete = false

    private var manifest: OfflineManifest? { store.manifest(for: trip) }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if let manifest {
                    citiesSection(manifest)
                    if !manifest.dayMaps.isEmpty { dayMapsSection(manifest) }
                    if !manifest.places.isEmpty { placesSection(manifest) }
                } else {
                    citiesSection(nil)
                }
                Section {
                    Label("BTS & MRT routes, the phrasebook, food guide, emergency numbers and your documents already work offline.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Offline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if manifest != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Delete Saved Pack", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .sheet(item: $viewingMap) { map in
                SavedDayMapView(map: map, url: store.imageURL(for: map, trip: trip))
            }
            .fullScreenCover(item: $showContent) { ShowModeView(content: $0) }
            .confirmationDialog("Delete the saved offline pack?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.delete(for: trip) }
            }
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let progress = store.progress {
                    ProgressView(value: progress) { Text("Saving offline pack…").font(.headline) } currentValueLabel: {
                        Text(store.progressText).lineLimit(1)
                    }
                    .tint(Theme.lagoon)
                    Text("Keep the app open. This takes about a second per stop.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let manifest {
                    Label("Saved \(manifest.createdAt.formatted(.relative(presentation: .named)))", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(Theme.lagoon)
                    HStack(spacing: 8) {
                        StatPill(systemImage: "figure.walk", text: "\(manifest.legs.count) routes", tint: Theme.lagoon)
                        StatPill(systemImage: "map", text: "\(manifest.dayMaps.count) day maps", tint: Theme.mango)
                        StatPill(systemImage: "character.bubble", text: "\(manifest.places.filter { $0.thaiAddress != nil }.count) Thai addresses")
                    }
                    if manifest.failedLegs > 0 {
                        Text("\(manifest.failedLegs) route\(manifest.failedLegs == 1 ? "" : "s") couldn't be saved (no walking path, e.g. across water).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Added or moved stops since then? Save again before you lose signal.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Save this trip for offline use").font(.headline)
                    Text("Walking routes between your stops (with turn-by-turn steps), a map picture of each day, and every place's address in Thai to show drivers.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if store.progress == nil {
                    Button {
                        Task { await store.build(for: trip) }
                    } label: {
                        Label(manifest == nil ? "Save Offline Pack" : "Update Offline Pack", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.primary)
                    .disabled(!network.isOnline)
                    if !network.isOnline {
                        OfflineBadge(text: "Needs internet to save")
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: Cities

    @ViewBuilder
    private func citiesSection(_ manifest: OfflineManifest?) -> some View {
        let cities: [OfflineCity] = manifest?.cities ?? Self.guessCities(for: trip)
        Section {
            if cities.isEmpty {
                Text("Add places with locations to your trip, and the cities to download show up here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(cities) { city in
                CityDownloadRow(city: city, store: store)
            }
        } header: {
            Text("Download maps for each city")
        } footer: {
            Text("Apple and Google don't let other apps download their maps, so do this in each app once, on Wi-Fi. Afterwards “Walk There” hand-offs keep working with no signal. Apple Maps: profile picture → Offline Maps → Download New Map. Google Maps: profile picture → Offline maps → Select your own map.")
        }
    }

    static func guessCities(for trip: Trip) -> [OfflineCity] {
        var counts: [String: (OfflineCoordinate, Int)] = [:]
        for item in trip.allItems {
            guard let c = item.coordinate, let city = ThaiCity.nearest(to: c) else { continue }
            counts[city.name, default: (OfflineCoordinate(CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)), 0)].1 += 1
        }
        return counts.map { OfflineCity(name: $0.key, center: $0.value.0, placeCount: $0.value.1) }.sorted { $0.placeCount > $1.placeCount }
    }

    // MARK: Saved content

    private func dayMapsSection(_ manifest: OfflineManifest) -> some View {
        Section("Saved day maps") {
            ForEach(manifest.dayMaps) { map in
                Button { viewingMap = map } label: {
                    HStack {
                        Label(map.title, systemImage: "map.fill")
                        Spacer()
                        Text("\(map.stopCount) stops").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func placesSection(_ manifest: OfflineManifest) -> some View {
        Section {
            ForEach(manifest.places) { place in
                Button {
                    showContent = ShowModeContent(
                        thai: "ไปที่ \(place.name)\n\(place.thaiAddress ?? "")",
                        english: "Please take me to \(place.name)." + (place.address.map { "\n\($0)" } ?? "")
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).foregroundStyle(.primary)
                        if let thai = place.thaiAddress { Text(thai).font(.caption).foregroundStyle(.secondary) }
                        if let label = place.dayLabel { Text(label).font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
            }
        } header: {
            Text("Show the driver")
        } footer: {
            Text("Tap a place to show its name and Thai address full-screen.")
        }
    }
}

private struct CityDownloadRow: View {
    let city: OfflineCity
    @ObservedObject var store: OfflinePackStore
    @Environment(\.openURL) private var openURL

    private func key(_ app: String) -> String { "\(city.name)|\(app)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(city.name).font(.headline)
                Spacer()
                Text("\(city.placeCount) place\(city.placeCount == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                appButton(title: "Apple Maps", app: "apple") {
                    let c = city.center
                    openURL(URL(string: "maps://?ll=\(c.lat),\(c.lon)&z=12")!)
                }
                appButton(title: "Google Maps", app: "google") {
                    let c = city.center
                    if let app = URL(string: "comgooglemaps://?center=\(c.lat),\(c.lon)&zoom=12"), UIApplication.shared.canOpenURL(app) {
                        openURL(app)
                    } else {
                        openURL(URL(string: "https://www.google.com/maps/@\(c.lat),\(c.lon),12z")!)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func appButton(title: String, app: String, open: @escaping () -> Void) -> some View {
        let done = store.confirmedDownloads.contains(key(app))
        return Menu {
            Button("Open \(title) here", systemImage: "arrow.up.forward.app", action: open)
            Button(done ? "Mark as Not Downloaded" : "I've Downloaded It", systemImage: done ? "xmark.circle" : "checkmark.circle") {
                if done { store.confirmedDownloads.remove(key(app)) } else { store.confirmedDownloads.insert(key(app)) }
            }
        } label: {
            Label(title, systemImage: done ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(done ? Theme.lagoon : Theme.mango)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background((done ? Theme.lagoon : Theme.mango).opacity(0.13), in: Capsule())
        }
    }
}

/// Zoomable saved map picture for one day.
struct SavedDayMapView: View {
    let map: OfflineDayMap
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            Group {
                if let url, let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: UIScreen.main.bounds.width * scale * pinch)
                    }
                    .gesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { scale = min(max(scale * $0.magnification, 1), 5) })
                } else {
                    ContentUnavailableView("Map not found", systemImage: "map", description: Text("Save the offline pack again."))
                }
            }
            .navigationTitle(map.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
