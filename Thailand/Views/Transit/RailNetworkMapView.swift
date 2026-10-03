import MapKit
import SwiftUI

/// Track geometry for each line (bundled BangkokRailShapes.json, from OpenStreetMap).
/// Lines without a shape fall back to straight segments between their stations.
enum RailShapes {
    private struct File: Decodable {
        let source: String
        let shapes: [String: [[[Double]]]]
    }

    static let byLine: [String: [[CLLocationCoordinate2D]]] = {
        guard let url = Bundle.main.url(forResource: "BangkokRailShapes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.shapes.mapValues { segments in
            segments.map { $0.compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil } }
        }
    }()

    static func paths(for line: RailLine) -> [[CLLocationCoordinate2D]] {
        if let shape = byLine[line.id], !shape.isEmpty { return shape }
        return [line.stations.map(\.coordinate)]
    }
}

/// Every BTS / MRT / ARL / SRT line drawn along its track in its own color, with stations.
struct RailNetworkMapView: View {
    /// Called with a station to plan a ride there (from the BTS & MRT screen).
    var onPlanTo: ((RailStation) -> Void)?
    var onShowStation: ((RailStation) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var location = LocationService.shared
    private let rail = BangkokRail.shared

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 13.765, longitude: 100.55),
        span: MKCoordinateSpan(latitudeDelta: 0.24, longitudeDelta: 0.2)))
    @State private var focusedLine: String?
    @State private var selected: StationPin?
    @State private var zoomedIn = false

    /// One pin per physical station; interchanges list every line that stops there.
    struct StationPin: Identifiable, Hashable {
        let station: RailStation
        let lines: [RailLine]
        var id: String { station.code }
    }

    private var pins: [StationPin] {
        var byName: [String: StationPin] = [:]
        for line in rail.lines {
            for station in line.stations {
                let key = station.en.lowercased()
                if let existing = byName[key],
                   existing.station.location.distance(from: station.location) < BangkokRail.transferRadius {
                    byName[key] = StationPin(station: existing.station, lines: existing.lines + [line])
                } else if byName[key] == nil {
                    byName[key] = StationPin(station: station, lines: [line])
                } else {
                    byName[key + station.code] = StationPin(station: station, lines: [line])
                }
            }
        }
        return Array(byName.values)
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selected) {
                UserAnnotation()
                ForEach(rail.lines) { line in
                    let dim = focusedLine != nil && focusedLine != line.id
                    ForEach(Array(RailShapes.paths(for: line).enumerated()), id: \.offset) { _, path in
                        // White casing under the colored line keeps it readable on the map.
                        MapPolyline(coordinates: path)
                            .stroke(.white.opacity(dim ? 0.2 : 0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: path)
                            .stroke(Color(hex: line.color).opacity(dim ? 0.15 : 1),
                                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    }
                }
                ForEach(pins.filter { pin in focusedLine == nil || pin.lines.contains { $0.id == focusedLine } }) { pin in
                    Annotation(pin.station.en, coordinate: pin.station.coordinate) {
                        StationDot(lines: pin.lines, interchange: pin.lines.count > 1, large: zoomedIn)
                    }
                    .annotationTitles(zoomedIn ? .automatic : .hidden)
                    .tag(pin)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                zoomedIn = context.region.span.latitudeDelta < 0.06
            }
            .safeAreaInset(edge: .top) { legend }
            .safeAreaInset(edge: .bottom) {
                if let selected { stationCard(selected) }
            }
            .navigationTitle("Rail Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { location.requestPermission() }
        }
    }

    /// Tap a line to show only it; tap again for all lines.
    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(rail.lines) { line in
                    Button {
                        withAnimation { focusedLine = focusedLine == line.id ? nil : line.id }
                        if focusedLine == line.id, let first = line.stations.first, let last = line.stations.last {
                            fit(line.stations.map(\.coordinate) + [first.coordinate, last.coordinate])
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Capsule().fill(Color(hex: line.color)).frame(width: 14, height: 5)
                            Text(line.short).font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(focusedLine == line.id ? Color(hex: line.color).opacity(0.25) : Color.clear,
                                    in: Capsule())
                        .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private func fit(_ coordinates: [CLLocationCoordinate2D]) {
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.3 + 0.01, longitudeDelta: (maxLon - minLon) * 1.3 + 0.01)))
        }
    }

    private func stationCard(_ pin: StationPin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pin.station.en).font(.headline)
                    Text(pin.station.th).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(pin.lines) { LineBadge(line: $0) }
                    }
                }
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .foregroundStyle(.secondary)
            }
            if let here = location.lastLocation {
                let meters = pin.station.location.distance(from: here)
                Text("\(Distance.text(meters * BangkokRail.detourFactor)) · \(Int(BangkokRail.walkMinutes(meters * BangkokRail.detourFactor).rounded())) min walk")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let onPlanTo {
                    Button {
                        onPlanTo(pin.station)
                        dismiss()
                    } label: { Label("Ride here", systemImage: "tram.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.mango)
                }
                if let onShowStation {
                    Button { onShowStation(pin.station) } label: {
                        Label("Show in Thai", systemImage: "text.bubble").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.horizontal)
    }
}

/// White station dot ringed in the line color (thicker, split ring at interchanges).
private struct StationDot: View {
    let lines: [RailLine]
    let interchange: Bool
    let large: Bool

    var body: some View {
        let size: CGFloat = (interchange ? 13 : 9) + (large ? 3 : 0)
        Circle()
            .fill(.white)
            .frame(width: size, height: size)
            .overlay {
                if interchange {
                    Circle().strokeBorder(
                        AngularGradient(colors: lines.map { Color(hex: $0.color) } + [Color(hex: lines[0].color)], center: .center),
                        lineWidth: 3)
                } else {
                    Circle().strokeBorder(Color(hex: lines.first?.color ?? "#888888"), lineWidth: 2.5)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 1)
            .accessibilityLabel(lines.map(\.short).joined(separator: ", "))
    }
}
