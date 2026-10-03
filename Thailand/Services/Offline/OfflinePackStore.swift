import Foundation
import MapKit
import UIKit

// MARK: - Saved data

struct OfflineCoordinate: Codable, Equatable {
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
}

struct OfflineStep: Codable, Equatable {
    var instructions: String
    var distance: Double
}

/// A walking route saved while online, reused when there's no signal.
struct OfflineLeg: Codable, Equatable {
    var from: OfflineCoordinate
    var to: OfflineCoordinate
    var points: [OfflineCoordinate]
    var meters: Double
    var seconds: Double
    var steps: [OfflineStep]
}

struct OfflinePlace: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var location: OfflineCoordinate
    var thaiAddress: String?
    var address: String?
    var dayLabel: String?
}

struct OfflineDayMap: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var fileName: String
    var stopCount: Int
}

struct OfflineCity: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var center: OfflineCoordinate
    var placeCount: Int
}

struct OfflineManifest: Codable, Equatable {
    var tripID: String
    var createdAt: Date
    var places: [OfflinePlace]
    var legs: [OfflineLeg]
    var dayMaps: [OfflineDayMap]
    var cities: [OfflineCity]
    var failedLegs: Int
}

/// Cities travelers usually visit, for grouping places and the "download this area" checklist.
enum ThaiCity {
    static let all: [(name: String, lat: Double, lon: Double)] = [
        ("Bangkok", 13.7563, 100.5018), ("Chiang Mai", 18.7883, 98.9853), ("Chiang Rai", 19.9105, 99.8406),
        ("Phuket", 7.8804, 98.3923), ("Krabi & Ao Nang", 8.0863, 98.9063), ("Koh Samui", 9.5120, 100.0136),
        ("Koh Phangan", 9.7380, 100.0136), ("Koh Tao", 10.0956, 99.8404), ("Koh Phi Phi", 7.7407, 98.7784),
        ("Koh Lanta", 7.6240, 99.0790), ("Pattaya", 12.9236, 100.8825), ("Hua Hin", 12.5684, 99.9577),
        ("Ayutthaya", 14.3532, 100.5689), ("Kanchanaburi", 14.0228, 99.5328), ("Pai", 19.3583, 98.4400),
        ("Sukhothai", 17.0076, 99.8230), ("Koh Chang", 12.0566, 102.3290), ("Khao Lak", 8.6367, 98.2487),
    ]

    static func nearest(to c: CLLocationCoordinate2D, within km: Double = 45) -> (name: String, lat: Double, lon: Double)? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return all
            .map { ($0, here.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon))) }
            .filter { $0.1 <= km * 1000 }
            .min { $0.1 < $1.1 }?.0
    }
}

// MARK: - Store

/// Builds and reads the per-trip offline pack (Application Support/Offline/<trip>/).
@MainActor
final class OfflinePackStore: ObservableObject {
    static let shared = OfflinePackStore()

    @Published private(set) var progress: Double?
    @Published private(set) var progressText = ""
    @Published private(set) var manifests: [String: OfflineManifest] = [:]

    /// Which cities you've confirmed downloading in Apple / Google Maps ("Bangkok|apple").
    @Published var confirmedDownloads: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "offlineConfirmedDownloads") ?? []) {
        didSet { UserDefaults.standard.set(Array(confirmedDownloads), forKey: "offlineConfirmedDownloads") }
    }

    private var root: URL {
        URL.applicationSupportDirectory.appending(path: "Offline", directoryHint: .isDirectory)
    }

    private func folder(for tripID: String) -> URL {
        let url = root.appending(path: tripID, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for dir in dirs {
            if let data = try? Data(contentsOf: dir.appending(path: "manifest.json")),
               let manifest = try? decoder.decode(OfflineManifest.self, from: data) {
                manifests[manifest.tripID] = manifest
            }
        }
    }

    func manifest(for trip: Trip) -> OfflineManifest? {
        trip.uuid.flatMap { manifests[$0.uuidString] }
    }

    func imageURL(for map: OfflineDayMap, trip: Trip) -> URL? {
        trip.uuid.map { folder(for: $0.uuidString).appending(path: map.fileName) }
    }

    func delete(for trip: Trip) {
        guard let id = trip.uuid?.uuidString else { return }
        try? FileManager.default.removeItem(at: folder(for: id))
        manifests[id] = nil
    }

    var isBuilding: Bool { progress != nil }

    // MARK: Lookups used offline

    /// A saved walking route that ends at `destination` (and ideally starts near `origin`).
    func cachedLeg(to destination: CLLocationCoordinate2D, from origin: CLLocationCoordinate2D?) -> OfflineLeg? {
        let end = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let candidates = manifests.values.flatMap(\.legs).filter {
            end.distance(from: CLLocation(latitude: $0.to.lat, longitude: $0.to.lon)) < 40
        }
        guard let origin else { return candidates.first }
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return candidates.min {
            start.distance(from: CLLocation(latitude: $0.from.lat, longitude: $0.from.lon)) <
            start.distance(from: CLLocation(latitude: $1.from.lat, longitude: $1.from.lon))
        }
    }

    func cachedLeg(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> OfflineLeg? {
        guard let leg = cachedLeg(to: destination, from: origin) else { return nil }
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return start.distance(from: CLLocation(latitude: leg.from.lat, longitude: leg.from.lon)) < 40 ? leg : nil
    }

    // MARK: Build

    /// Saves routes, day maps and Thai addresses for every scheduled stop. Needs internet.
    func build(for trip: Trip) async {
        guard let tripID = trip.uuid?.uuidString, !isBuilding else { return }
        progress = 0
        progressText = "Getting ready…"
        defer { progress = nil; progressText = "" }

        let dir = folder(for: tripID)
        let hotel = trip.sortedSavedPlaces.first
        var places: [OfflinePlace] = []
        var legs: [OfflineLeg] = []
        var dayMaps: [OfflineDayMap] = []
        var failed = 0

        // Work list: each day's stops in order (starting from your first saved place, e.g. the hotel).
        var dayPlans: [(day: Day, points: [(id: String, name: String, coordinate: CLLocationCoordinate2D, item: Item?)])] = []
        for day in trip.sortedDays {
            var points = day.sortedItems.compactMap { item -> (String, String, CLLocationCoordinate2D, Item?)? in
                guard let c = item.coordinate else { return nil }
                return (item.uuid?.uuidString ?? UUID().uuidString, item.displayTitle, c, item)
            }
            if let hotel, !points.isEmpty,
               CLLocation(latitude: hotel.latitude, longitude: hotel.longitude).distance(from: CLLocation(latitude: points[0].2.latitude, longitude: points[0].2.longitude)) < 30_000 {
                points.insert((hotel.uuid?.uuidString ?? "hotel", hotel.displayName, hotel.coordinate, nil), at: 0)
            }
            if !points.isEmpty { dayPlans.append((day, points)) }
        }
        let wishPoints = trip.allItems.filter(\.isOnWishList).compactMap { item -> OfflinePlace? in
            guard let c = item.coordinate else { return nil }
            return OfflinePlace(id: item.uuid?.uuidString ?? UUID().uuidString, name: item.displayTitle, location: OfflineCoordinate(c), address: item.address, dayLabel: "Wish List")
        }

        let legCount = dayPlans.reduce(0) { $0 + max($1.points.count - 1, 0) }
        let placeCount = dayPlans.reduce(0) { $0 + $1.points.count } + wishPoints.count + trip.sortedSavedPlaces.count
        let totalWork = Double(max(legCount + dayPlans.count + placeCount, 1))
        var done = 0.0
        func tick(_ text: String) { done += 1; progress = min(done / totalWork, 1); progressText = text }

        // 1. Walking routes between stops.
        for plan in dayPlans {
            for index in plan.points.indices.dropFirst() {
                let a = plan.points[index - 1], b = plan.points[index]
                tick("Saving route to \(b.name)")
                if let leg = await Self.walkingLeg(from: a.coordinate, to: b.coordinate) {
                    legs.append(leg)
                } else {
                    failed += 1
                }
            }
        }

        // 2. A map picture per day with numbered stops and routes.
        for plan in dayPlans {
            tick("Drawing map for \(plan.day.heading)")
            let dayLegs = legs.filter { leg in plan.points.contains { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: CLLocation(latitude: leg.to.lat, longitude: leg.to.lon)) < 5 } }
            if let image = await Self.snapshot(points: plan.points.map(\.coordinate), legs: dayLegs, firstIsHotel: hotel != nil && plan.points.first?.item == nil),
               let data = image.jpegData(compressionQuality: 0.85) {
                let name = "day-\(plan.day.uuid?.uuidString ?? UUID().uuidString).jpg"
                try? data.write(to: dir.appending(path: name), options: .atomic)
                dayMaps.append(OfflineDayMap(id: name, title: plan.day.heading, fileName: name, stopCount: plan.points.count))
            }
        }

        // 3. Thai addresses (to show drivers), throttled to respect Apple's geocoder limits.
        var seen = Set<String>()
        let allPoints: [OfflinePlace] =
            trip.sortedSavedPlaces.map { OfflinePlace(id: $0.uuid?.uuidString ?? UUID().uuidString, name: $0.displayName, location: OfflineCoordinate($0.coordinate), address: $0.address, dayLabel: "Saved place") }
            + dayPlans.flatMap { plan in plan.points.compactMap { p in p.item.map { OfflinePlace(id: p.id, name: p.name, location: OfflineCoordinate(p.coordinate), address: $0.address, dayLabel: plan.day.heading) } } }
            + wishPoints
        for var place in allPoints where !seen.contains(place.id) {
            seen.insert(place.id)
            tick("Looking up Thai address for \(place.name)")
            if places.count < 80 {
                place.thaiAddress = await Self.thaiAddress(for: place.location.coordinate)
                try? await Task.sleep(for: .milliseconds(700))
            }
            places.append(place)
        }

        // 4. Cities to download in Apple / Google Maps.
        var cityCounts: [String: (center: OfflineCoordinate, count: Int)] = [:]
        for place in places {
            if let city = ThaiCity.nearest(to: place.location.coordinate) {
                cityCounts[city.name, default: (OfflineCoordinate(CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)), 0)].count += 1
            }
        }
        let cities = cityCounts.map { OfflineCity(name: $0.key, center: $0.value.center, placeCount: $0.value.count) }.sorted { $0.placeCount > $1.placeCount }

        let manifest = OfflineManifest(tripID: tripID, createdAt: .now, places: places, legs: legs, dayMaps: dayMaps, cities: cities, failedLegs: failed)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: dir.appending(path: "manifest.json"), options: .atomic)
        }
        manifests[tripID] = manifest
    }

    // MARK: Helpers

    private static func walkingLeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> OfflineLeg? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        let polyline = route.polyline
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        // Thin very long routes to keep the file small.
        let stride = max(1, coords.count / 400)
        let thinned = Swift.stride(from: 0, to: coords.count, by: stride).map { coords[$0] } + [coords.last].compactMap { $0 }
        return OfflineLeg(
            from: OfflineCoordinate(from),
            to: OfflineCoordinate(to),
            points: thinned.map(OfflineCoordinate.init),
            meters: route.distance,
            seconds: route.expectedTravelTime,
            steps: route.steps.filter { !$0.instructions.isEmpty }.map { OfflineStep(instructions: $0.instructions, distance: $0.distance) }
        )
    }

    private static func thaiAddress(for coordinate: CLLocationCoordinate2D) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            preferredLocale: Locale(identifier: "th_TH")
        )
        guard let p = placemarks?.first else { return nil }
        let parts = [p.name, p.thoroughfare, p.subLocality, p.locality, p.administrativeArea].compactMap { $0 }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? nil : unique.joined(separator: " ")
    }

    private static func snapshot(points: [CLLocationCoordinate2D], legs: [OfflineLeg], firstIsHotel: Bool) async -> UIImage? {
        let all = points + legs.flatMap { $0.points.map(\.coordinate) }
        guard !all.isEmpty else { return nil }
        let lats = all.map(\.latitude), lons = all.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.35, 0.008), longitudeDelta: max((lons.max()! - lons.min()!) * 1.35, 0.008))

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 1000, height: 1000)
        options.scale = 2
        options.pointOfInterestFilter = .includingAll
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: snap.image.size)
        return renderer.image { ctx in
            snap.image.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(9)
            cg.setStrokeColor(UIColor(hex: "#1BA39C").withAlphaComponent(0.85).cgColor)
            for leg in legs {
                let pts = leg.points.map { snap.point(for: $0.coordinate) }
                guard let first = pts.first else { continue }
                cg.beginPath()
                cg.move(to: first)
                pts.dropFirst().forEach { cg.addLine(to: $0) }
                cg.strokePath()
            }
            for (index, coordinate) in points.enumerated() {
                let p = snap.point(for: coordinate)
                let rect = CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: rect.insetBy(dx: -4, dy: -4))
                cg.setFillColor(UIColor(hex: index == 0 && firstIsHotel ? "#6C5CE7" : "#F4821C").cgColor)
                cg.fillEllipse(in: rect)
                let label = index == 0 && firstIsHotel ? "H" : "\(firstIsHotel ? index : index + 1)"
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22, weight: .heavy), .foregroundColor: UIColor.white]
                let size = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
            }
        }
    }
}
