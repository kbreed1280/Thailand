import SwiftUI
import MapKit
import CoreData

/// Day route planner: numbered stops on the map with real routes between them, an optional
/// start/end saved place (e.g. the hotel), drag-to-reorder that can re-time the day, and
/// hand-off to Apple or Google Maps.
struct DayMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var day: Day

    @State private var position: MapCameraPosition = .automatic
    @State private var walkTarget: WalkTarget?
    @State private var startPlaceID: UUID?
    @State private var endPlaceID: UUID?
    @State private var routes: [MKRoute] = []
    /// Routes from the offline pack, drawn when there's no internet.
    @State private var savedLines: [[CLLocationCoordinate2D]] = []
    @State private var legSeconds: [TimeInterval] = []
    @State private var isRouting = false
    @State private var refreshTick = 0
    @State private var retimeMessage: String?

    private var store: ItineraryStore { ItineraryStore(context: context) }
    private var savedPlaces: [SavedPlace] { day.trip?.sortedSavedPlaces ?? [] }
    private var startPlace: SavedPlace? { savedPlaces.first { $0.uuid == startPlaceID } }
    private var endPlace: SavedPlace? { savedPlaces.first { $0.uuid == endPlaceID } }

    private var stops: [(number: Int, item: Item)] {
        day.sortedItems
            .filter(\.hasCoordinate)
            .enumerated()
            .map { (number: $0.offset + 1, item: $0.element) }
    }

    /// Start place, stops, end place — the points the route goes through.
    private var routePoints: [CLLocationCoordinate2D] {
        [startPlace?.coordinate].compactMap { $0 } + stops.compactMap(\.item.coordinate) + [endPlace?.coordinate].compactMap { $0 }
    }

    private var routeKey: String {
        routePoints.map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }.joined(separator: ";")
            + "|" + stops.map { $0.item.travelModeRaw ?? "" }.joined()
    }

    var body: some View {
        let _ = refreshTick
        NavigationStack {
            VStack(spacing: 0) {
                map
                    .frame(height: 300)
                stopList
            }
            .navigationTitle(day.heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            .fullScreenCover(item: $walkTarget) { target in
                WalkingRouteView(destinationName: target.name, coordinate: target.coordinate)
            }
            .task(id: routeKey) { await calculateRoutes() }
            .onAppear {
                LocationService.shared.requestPermission()
                if startPlaceID == nil { startPlaceID = savedPlaces.first?.uuid }
                if endPlaceID == nil { endPlaceID = savedPlaces.first?.uuid }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                refreshTick &+= 1
            }
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                MapPolyline(route)
                    .stroke(Theme.lagoon, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(savedLines.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line)
                    .stroke(Theme.lagoon, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [8, 6]))
            }
            ForEach(stops, id: \.number) { stop in
                Annotation(stop.item.displayTitle, coordinate: stop.item.coordinate ?? CLLocationCoordinate2D()) {
                    NumberedPin(number: stop.number, colorHex: stop.item.category.colorHex, isSelected: false)
                }
            }
            ForEach(endpoints, id: \.id) { endpoint in
                Annotation(endpoint.name, coordinate: endpoint.coordinate) {
                    Image(systemName: endpoint.symbol)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .topTrailing) {
            if isRouting {
                ProgressView().padding(8).background(.regularMaterial, in: Circle()).padding()
            }
        }
    }

    private struct Endpoint {
        let id: String
        let name: String
        let symbol: String
        let coordinate: CLLocationCoordinate2D
    }

    private var endpoints: [Endpoint] {
        var result: [Endpoint] = []
        if let startPlace {
            result.append(Endpoint(id: "start", name: "Start: \(startPlace.displayName)", symbol: startPlace.symbolName ?? "house.fill", coordinate: startPlace.coordinate))
        }
        if let endPlace, endPlace != startPlace {
            result.append(Endpoint(id: "end", name: "End: \(endPlace.displayName)", symbol: endPlace.symbolName ?? "house.fill", coordinate: endPlace.coordinate))
        }
        return result
    }

    // MARK: List

    private var stopList: some View {
        List {
            if !savedPlaces.isEmpty {
                Section {
                    Picker("Start from", selection: $startPlaceID) {
                        Text("First stop").tag(UUID?.none)
                        ForEach(savedPlaces) { place in
                            Label(place.displayName, systemImage: place.symbolName ?? "mappin").tag(place.uuid)
                        }
                    }
                    Picker("End at", selection: $endPlaceID) {
                        Text("Last stop").tag(UUID?.none)
                        ForEach(savedPlaces) { place in
                            Label(place.displayName, systemImage: place.symbolName ?? "mappin").tag(place.uuid)
                        }
                    }
                }
            }

            Section {
                ForEach(day.sortedItems) { item in
                    stopRow(item)
                }
                .onMove { source, destination in
                    store.reorder(day.sortedItems, fromOffsets: source, toOffset: destination)
                    store.save()
                }
            } header: {
                Text("Stops — drag to reorder")
            } footer: {
                if let retimeMessage {
                    Text(retimeMessage)
                } else {
                    Text("Arrival times assume each stop's duration plus travel time and a 5-minute buffer.")
                }
            }

            Section {
                Button {
                    retime()
                } label: {
                    Label("Re-time Day from First Stop", systemImage: "clock.arrow.2.circlepath")
                }
                .disabled(stops.count < 2 || legSeconds.isEmpty)

                Button {
                    ExternalApps.openGoogleMaps(stops: googleStops, travelMode: stops.first?.item.travelMode.googleMode ?? "walking")
                } label: {
                    Label("Open Route in Google Maps", systemImage: "map.fill")
                }
                .disabled(stops.isEmpty)

                Button {
                    ExternalApps.openAppleMapsRoute(stops.compactMap { stop in
                        stop.item.coordinate.map { (name: stop.item.displayTitle, coordinate: $0) }
                    }, walking: stops.first?.item.travelMode == .walking)
                } label: {
                    Label("Open Route in Apple Maps", systemImage: "apple.logo")
                }
                .disabled(stops.isEmpty)

                if let first = stops.first, let coordinate = first.item.coordinate {
                    Button {
                        ExternalApps.openAppleMaps(to: coordinate, name: first.item.displayTitle, walking: first.item.travelMode == .walking)
                    } label: {
                        Label("Open First Stop in Apple Maps", systemImage: "apple.logo")
                    }
                    Button {
                        walkTarget = WalkTarget(name: first.item.displayTitle, coordinate: coordinate)
                    } label: {
                        Label("Walk to First Stop (in app)", systemImage: "figure.walk")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func stopRow(_ item: Item) -> some View {
        let number = stops.first { $0.item == item }?.number
        return HStack(spacing: 12) {
            if let number {
                NumberedPin(number: number, colorHex: item.category.colorHex, isSelected: false, compact: true)
            } else {
                Image(systemName: "mappin.slash")
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    if let time = item.time {
                        Text(time.formatted(date: .omitted, time: .shortened))
                    }
                    Text("· \(ScheduleMath.durationText(seconds: TimeInterval(item.durationMinutes * 60)))")
                    if let arrival = estimatedArrival(for: item) {
                        Text("· arrive ~\(arrival.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(Theme.lagoon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let coordinate = item.coordinate {
                Button {
                    walkTarget = WalkTarget(name: item.displayTitle, coordinate: coordinate)
                } label: {
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.lagoon)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Walk to \(item.displayTitle)")
            }
        }
    }

    // MARK: Routing

    private var googleStops: [CLLocationCoordinate2D] {
        // Google starts from your current location, so only add the end place after the stops.
        stops.compactMap(\.item.coordinate) + [endPlace?.coordinate].compactMap { $0 }
    }

    private func calculateRoutes() async {
        let points = routePoints
        guard points.count > 1 else {
            routes = []
            legSeconds = []
            return
        }
        isRouting = true
        defer { isRouting = false }

        let offset = startPlace == nil ? 0 : 1
        var newRoutes: [MKRoute] = []
        var newSaved: [[CLLocationCoordinate2D]] = []
        var seconds: [TimeInterval] = []
        for index in 1..<points.count {
            // Travel mode belongs to the stop you're heading to; the end place uses walking.
            let stopIndex = index - offset
            let mode = stops.indices.contains(stopIndex) ? stops[stopIndex].item.travelMode : .walking
            if let route = await TravelTimeService.shared.route(from: points[index - 1], to: points[index], mode: mode) {
                newRoutes.append(route)
                seconds.append(route.expectedTravelTime)
            } else if let saved = OfflinePackStore.shared.cachedLeg(from: points[index - 1], to: points[index]) {
                newSaved.append(saved.points.map(\.coordinate))
                seconds.append(mode == .walking ? saved.seconds : 0)
            } else {
                seconds.append(0)
            }
        }
        routes = newRoutes
        savedLines = newSaved
        // Keep only the legs between stops for re-timing.
        legSeconds = Array(seconds.dropFirst(offset).prefix(max(stops.count - 1, 0)))
    }

    /// Arrival estimate: previous stop's end + travel time.
    private func estimatedArrival(for item: Item) -> Date? {
        guard let index = stops.firstIndex(where: { $0.item == item }), index > 0,
              let previousEnd = stops[index - 1].item.endTime,
              legSeconds.indices.contains(index - 1), legSeconds[index - 1] > 0 else { return nil }
        return previousEnd.addingTimeInterval(legSeconds[index - 1])
    }

    /// Rewrites start times after reordering, keeping durations and travel gaps.
    private func retime() {
        guard let date = day.date, stops.count > 1 else { return }
        let calendar = Calendar.current
        let firstStart = stops[0].item.time
            ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
            ?? date
        let starts = ScheduleMath.retimedStarts(
            firstStart: firstStart,
            durationsMinutes: stops.map { Int($0.item.durationMinutes) },
            travelSeconds: legSeconds
        )
        for (stop, start) in zip(stops, starts) {
            stop.item.time = start
            stop.item.markEdited()
        }
        store.save()
        retimeMessage = "Times updated: first stop \(firstStart.formatted(date: .omitted, time: .shortened)), last at \(starts.last?.formatted(date: .omitted, time: .shortened) ?? "")."
    }
}

struct NumberedPin: View {
    let number: Int
    let colorHex: String
    let isSelected: Bool
    var compact = false

    private var size: CGFloat { compact ? 30 : (isSelected ? 42 : 34) }

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: compact ? 0 : 2.5))
            .shadow(color: .black.opacity(compact ? 0 : 0.3), radius: 3, y: 2)
            .animation(.spring(duration: 0.25), value: isSelected)
            .accessibilityLabel("Stop \(number)")
    }
}
