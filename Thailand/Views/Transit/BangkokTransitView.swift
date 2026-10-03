import SwiftUI
import CoreLocation

/// A place you can route to or from: your location, a trip stop, a saved place or a station.
struct RailEndpoint: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let coordinate: CLLocationCoordinate2D?

    static let myLocation = RailEndpoint(id: "me", name: "My Location", systemImage: "location.fill", coordinate: nil)

    static func == (lhs: RailEndpoint, rhs: RailEndpoint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Bangkok BTS / MRT / Airport Rail Link helper. Works fully offline from bundled station data.
struct BangkokTransitView: View {
    let trip: Trip?
    var initialDestination: RailEndpoint?

    @ObservedObject private var location = LocationService.shared
    @State private var from: RailEndpoint = .myLocation
    @State private var to: RailEndpoint?
    @State private var choosing: Choosing?
    @State private var showContent: ShowModeContent?

    private let rail = BangkokRail.shared

    private enum Choosing: String, Identifiable {
        case from, to
        var id: String { rawValue }
    }

    var body: some View {
        List {
            plannerSection
            if let journey {
                Section("Your ride") {
                    RailJourneyCard(journey: journey, destinationName: to?.name ?? "") { station in
                        showContent = Self.showCard(for: station)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            } else if to != nil {
                Section {
                    Label(noRouteMessage, systemImage: "figure.walk")
                        .foregroundStyle(.secondary)
                }
            }
            nearbySection
            linesSection
            Section {
                Text("Times and fares are estimates. Buy a single-journey token or card at the machine or counter. MRT gates also take contactless bank cards. \(rail.attribution).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("BTS & MRT")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $choosing) { which in
            NavigationStack {
                RailEndpointPicker(trip: trip, includeMyLocation: true) { endpoint in
                    if which == .from { from = endpoint } else { to = endpoint }
                    choosing = nil
                }
            }
        }
        .fullScreenCover(item: $showContent) { content in
            ShowModeView(content: content)
        }
        .onAppear {
            if to == nil { to = initialDestination }
            location.requestPermission()
        }
    }

    // MARK: Sections

    private var plannerSection: some View {
        Section("Plan a ride") {
            endpointRow(label: "From", endpoint: from) { choosing = .from }
            endpointRow(label: "To", endpoint: to) { choosing = .to }
            if to != nil {
                Button {
                    if let destination = to {
                        to = from == .myLocation ? nil : from
                        from = destination
                    }
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func endpointRow(label: String, endpoint: RailEndpoint?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                if let endpoint {
                    Label(endpoint.name, systemImage: endpoint.systemImage).foregroundStyle(.primary)
                } else {
                    Text("Choose a stop or station").foregroundStyle(Theme.mango)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var nearbySection: some View {
        if let here = location.lastLocation?.coordinate {
            let nearest = rail.nearestStations(to: here, limit: 3)
            Section("Nearest stations") {
                if nearest.isEmpty {
                    Text(BangkokRail.covers(here) ? "No station within 3 km." : "You're outside Bangkok's rail network.")
                        .foregroundStyle(.secondary)
                }
                ForEach(nearest, id: \.station.code) { item in
                    Button {
                        to = RailEndpoint(id: "station-\(item.station.code)", name: "\(item.station.en) station", systemImage: "tram.fill", coordinate: item.station.coordinate)
                    } label: {
                        StationRow(station: item.station, lines: item.lines, detail: "\(Int(BangkokRail.walkMinutes(item.meters * BangkokRail.detourFactor).rounded())) min walk")
                    }
                }
            }
        }
    }

    private var linesSection: some View {
        Section("Lines") {
            ForEach(rail.lines) { line in
                NavigationLink {
                    RailLineView(line: line) { station in showContent = Self.showCard(for: station) }
                } label: {
                    HStack(spacing: 12) {
                        LineBadge(line: line)
                        VStack(alignment: .leading) {
                            Text(line.name)
                            Text("\(line.stations.first?.en ?? "") – \(line.stations.last?.en ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Routing

    private var fromCoordinate: CLLocationCoordinate2D? {
        from == .myLocation ? location.lastLocation?.coordinate : from.coordinate
    }

    private var journey: RailJourney? {
        guard let a = fromCoordinate, let b = to?.coordinate ?? (to == .myLocation ? location.lastLocation?.coordinate : nil) else { return nil }
        return rail.journey(from: a, to: b)
    }

    private var noRouteMessage: String {
        guard let a = fromCoordinate, let b = to?.coordinate else {
            return from == .myLocation ? "Waiting for your location…" : "This place has no map location."
        }
        if !BangkokRail.covers(a) || !BangkokRail.covers(b) { return "BTS and MRT only cover Bangkok." }
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        if meters < 2000 { return "It's quicker to walk (about \(Int(BangkokRail.walkMinutes(meters * BangkokRail.detourFactor).rounded())) min)." }
        return "No station within walking distance. A taxi or Grab is the better choice."
    }

    static func showCard(for station: RailStation) -> ShowModeContent {
        ShowModeContent(
            thai: "ไปสถานี\(station.th)\nครับ/ค่ะ",
            english: "Please take me to \(station.en) station (\(station.code))."
        )
    }
}

// MARK: - Journey card (also used on a stop's detail screen)

struct RailJourneyCard: View {
    let journey: RailJourney
    let destinationName: String
    var onShowStation: ((RailStation) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatPill(systemImage: "clock", text: "~\(Int(journey.totalMinutes.rounded())) min", tint: Theme.lagoon)
                StatPill(systemImage: "bahtsign", text: "≈ ฿\(Int(journey.fareTHB))", tint: Theme.mango)
                if journey.transfers > 0 {
                    StatPill(systemImage: "arrow.triangle.swap", text: journey.transfers == 1 ? "1 change" : "\(journey.transfers) changes")
                }
            }

            step(icon: "figure.walk", tint: .secondary,
                 title: "Walk to \(journey.boardAt.en)",
                 detail: "\(Int(journey.walkToMinutes.rounded())) min · \(formatMeters(journey.walkToStationMeters))")

            ForEach(Array(journey.rides.enumerated()), id: \.element.id) { index, ride in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        LineBadge(line: ride.line)
                        Text(index == 0 ? "Board at \(ride.from.en)" : "Change to the \(ride.line.short) line at \(ride.from.en)")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(directionText(ride))
                        .font(.subheadline)
                    Text("Ride \(ride.stops) stop\(ride.stops == 1 ? "" : "s") to \(ride.to.en) (\(ride.to.code))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: ride.line.color).opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
            }

            step(icon: "flag.checkered", tint: Theme.mango,
                 title: destinationName.isEmpty ? "Walk to your destination" : "Walk to \(destinationName)",
                 detail: "\(Int(journey.walkFromMinutes.rounded())) min · \(formatMeters(journey.walkFromStationMeters))")

            if let onShowStation {
                Button {
                    onShowStation(journey.boardAt)
                } label: {
                    Label("Show “\(journey.boardAt.en) station” in Thai", systemImage: "character.bubble")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.lagoon)
            }
        }
    }

    private func directionText(_ ride: RailRide) -> String {
        if ride.line.id == "mrt-blue", let next = ride.nextStop {
            return "Take the train whose next stop is \(next.en)"
        }
        return "Platform toward \(ride.terminus.en)"
    }

    private func step(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func formatMeters(_ meters: Double) -> String {
        meters < 1000 ? "\(Int((meters / 10).rounded() * 10)) m" : String(format: "%.1f km", meters / 1000)
    }
}

// MARK: - Pieces

struct LineBadge: View {
    let line: RailLine

    var body: some View {
        Text(line.system == "SRT" ? "SRT" : line.system)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(line.id == "mrt-yellow" ? .black : .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(hex: line.color), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(line.name)
    }
}

private struct StationRow: View {
    let station: RailStation
    let lines: [RailLine]
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(lines) { LineBadge(line: $0) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(station.en).foregroundStyle(.primary)
                Text(station.th).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct RailLineView: View {
    let line: RailLine
    var onShow: (RailStation) -> Void

    private let rail = BangkokRail.shared

    var body: some View {
        List {
            Section {
                ForEach(line.stations) { station in
                    Button {
                        onShow(station)
                    } label: {
                        HStack(spacing: 12) {
                            Text(station.code)
                                .font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(Color(hex: line.color))
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(station.en).foregroundStyle(.primary)
                                Text(station.th).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let others = rail.lines(serving: station).filter { $0.id != line.id }
                            ForEach(others) { LineBadge(line: $0) }
                        }
                    }
                }
            } footer: {
                Text("Tap a station to show its name in Thai.")
            }
        }
        .navigationTitle(line.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pick where to go: trip stops, saved places, or any station.
struct RailEndpointPicker: View {
    let trip: Trip?
    var includeMyLocation: Bool
    var onPick: (RailEndpoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private let rail = BangkokRail.shared

    private var tripPlaces: [RailEndpoint] {
        guard let trip else { return [] }
        let saved = trip.sortedSavedPlaces.map {
            RailEndpoint(id: "saved-\($0.objectID.uriRepresentation())", name: $0.displayName, systemImage: $0.symbolName ?? "mappin", coordinate: $0.coordinate)
        }
        let stops = trip.allItems.compactMap { item -> RailEndpoint? in
            guard let coordinate = item.coordinate, BangkokRail.covers(coordinate) else { return nil }
            return RailEndpoint(id: "item-\(item.objectID.uriRepresentation())", name: item.displayTitle, systemImage: item.category.systemImage, coordinate: coordinate)
        }
        return (saved + stops).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var stations: [(station: RailStation, lines: [RailLine])] {
        rail.stationDirectory.filter {
            search.isEmpty || $0.station.en.localizedCaseInsensitiveContains(search) || $0.station.th.contains(search) || $0.station.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if includeMyLocation, search.isEmpty {
                Button { onPick(.myLocation) } label: { Label("My Location", systemImage: "location.fill") }
            }
            if !tripPlaces.isEmpty {
                Section("From your trip (Bangkok)") {
                    ForEach(tripPlaces) { place in
                        Button { onPick(place) } label: { Label(place.name, systemImage: place.systemImage).foregroundStyle(.primary) }
                    }
                }
            }
            Section("Stations") {
                ForEach(stations, id: \.station.code) { entry in
                    Button {
                        onPick(RailEndpoint(id: "station-\(entry.station.code)", name: "\(entry.station.en) station", systemImage: "tram.fill", coordinate: entry.station.coordinate))
                    } label: {
                        StationRow(station: entry.station, lines: entry.lines)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Stop or station")
        .navigationTitle("Choose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}

/// "By BTS / MRT" on a Bangkok stop: from where you are now, or from the previous stop of the day.
struct StopRailCard: View {
    let item: Item
    let coordinate: CLLocationCoordinate2D

    @ObservedObject private var location = LocationService.shared
    @State private var showContent: ShowModeContent?
    @State private var useMyLocation = true

    private var previousStop: Item? {
        guard let items = item.day?.sortedItems, let index = items.firstIndex(of: item), index > 0 else { return nil }
        return items[..<index].last { $0.coordinate != nil }
    }

    private var origin: (name: String, coordinate: CLLocationCoordinate2D)? {
        if useMyLocation, let here = location.lastLocation?.coordinate, BangkokRail.covers(here) {
            return ("your location", here)
        }
        if let previous = previousStop, let coordinate = previous.coordinate {
            return (previous.displayTitle, coordinate)
        }
        return nil
    }

    var body: some View {
        let journey = origin.flatMap { BangkokRail.shared.journey(from: $0.coordinate, to: coordinate) }
        let nearest = BangkokRail.shared.nearestStations(to: coordinate, limit: 1).first

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("By BTS / MRT", systemImage: "tram.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if previousStop != nil, location.lastLocation != nil {
                    Picker("From", selection: $useMyLocation) {
                        Text("From here").tag(true)
                        Text("From last stop").tag(false)
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
            }
            if let journey, let origin {
                Text("From \(origin.name)").font(.caption).foregroundStyle(.secondary)
                RailJourneyCard(journey: journey, destinationName: item.displayTitle) { station in
                    showContent = BangkokTransitView.showCard(for: station)
                }
            } else if let nearest {
                Text("Nearest station: \(nearest.station.en) (\(nearest.station.code)), about \(Int(BangkokRail.walkMinutes(nearest.meters * BangkokRail.detourFactor).rounded())) min walk.")
                    .font(.subheadline)
            } else {
                Text("No BTS or MRT station within walking distance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                BangkokTransitView(
                    trip: item.trip,
                    initialDestination: RailEndpoint(id: "item-\(item.objectID.uriRepresentation())", name: item.displayTitle, systemImage: item.category.systemImage, coordinate: coordinate)
                )
            } label: {
                Label("Open BTS & MRT planner", systemImage: "arrow.right.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.lagoon)
        }
        .card()
        .fullScreenCover(item: $showContent) { ShowModeView(content: $0) }
    }
}
