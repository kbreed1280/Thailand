import CoreLocation
import Foundation
import MapKit
import UIKit

/// A 7-Eleven (or other convenience store) pin.
struct ConvenienceStore: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let openingHours: String?
    let branch: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var isOpen24h: Bool { openingHours == "24/7" }
}

/// Finds 7-Elevens from OpenStreetMap (free, thousands mapped across Thailand), cached on disk in
/// ~1 km tiles so the map keeps working offline. Falls back to Apple Maps search (max ~25 results).
enum SevenElevenService {
    /// Wikidata ID for the 7-Eleven brand, used by OpenStreetMap's brand tags.
    private static let brandTag = "Q259340"
    private static let servers = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]
    /// Tiles are 0.01° (~1.1 km) squares; the map loads at most this many per request.
    static let tileSize = 0.01
    static let maxTiles = 64

    /// Stores inside the region. Returns cached tiles immediately where possible; fetches the rest.
    static func stores(in region: MKCoordinateRegion) async -> (stores: [ConvenienceStore], zoomedOutTooFar: Bool) {
        let tiles = tileKeys(for: region)
        guard tiles.count <= maxTiles else { return ([], true) }

        var result: [ConvenienceStore] = []
        var missing: [TileKey] = []
        for tile in tiles {
            if let cached = cache(tile) { result += cached } else { missing.append(tile) }
        }
        if !missing.isEmpty, let bounds = boundingBox(of: missing) {
            if let fetched = await fetchOverpass(bounds) {
                for tile in missing {
                    store(fetched.filter { tile.contains($0.coordinate) }, for: tile)
                }
                result += fetched.filter { s in missing.contains { $0.contains(s.coordinate) } }
            } else if let apple = await fetchAppleMaps(region) {
                result += apple // not cached: Apple results are partial
            }
        }
        // De-duplicate (tiles can overlap stores on the border) and keep those in view.
        var seen = Set<String>()
        let unique = result.filter { seen.insert($0.id).inserted }
        return (unique.filter { region.contains($0.coordinate) }, false)
    }

    /// The nearest stores to a point, using cached/fetched tiles around it (~2 km box).
    static func nearest(to location: CLLocation, limit: Int = 5) async -> [ConvenienceStore] {
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000)
        return await stores(in: region).stores
            .sorted { $0.location.distance(from: location) < $1.location.distance(from: location) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Overpass (OpenStreetMap)

    private struct OverpassResponse: Decodable {
        struct Element: Decodable {
            let id: Int
            let lat: Double?
            let lon: Double?
            let center: Center?
            let tags: [String: String]?
            struct Center: Decodable { let lat: Double; let lon: Double }
        }
        let elements: [Element]
    }

    private static func fetchOverpass(_ box: (south: Double, west: Double, north: Double, east: Double)) async -> [ConvenienceStore]? {
        let bbox = "\(box.south),\(box.west),\(box.north),\(box.east)"
        let query = """
        [out:json][timeout:20];
        (node["brand:wikidata"="\(brandTag)"](\(bbox));way["brand:wikidata"="\(brandTag)"](\(bbox));
         node["shop"="convenience"]["name"~"7-Eleven|7-11|เซเว่น",i](\(bbox)););
        out center 2000;
        """
        for server in servers {
            guard let url = URL(string: server) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 25)
            request.httpMethod = "POST"
            request.setValue("WanderHub/1.0 (iOS travel app)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [URLQueryItem(name: "data", value: query)]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(OverpassResponse.self, from: data) else { continue }
            return decoded.elements.compactMap { e in
                guard let lat = e.lat ?? e.center?.lat, let lon = e.lon ?? e.center?.lon else { return nil }
                let tags = e.tags ?? [:]
                return ConvenienceStore(
                    id: "osm-\(e.id)",
                    name: tags["name:en"] ?? tags["name"] ?? "7-Eleven",
                    latitude: lat, longitude: lon,
                    openingHours: tags["opening_hours"],
                    branch: tags["branch"] ?? tags["branch:en"]
                )
            }
        }
        return nil
    }

    // MARK: Apple Maps fallback

    private static func fetchAppleMaps(_ region: MKCoordinateRegion) async -> [ConvenienceStore]? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "7-Eleven"
        request.region = region
        request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems
            .filter { ($0.name ?? "").range(of: "7-eleven|7-11|7 eleven", options: [.regularExpression, .caseInsensitive]) != nil }
            .map {
                let c = $0.placemark.coordinate
                return ConvenienceStore(id: "apple-\(c.latitude),\(c.longitude)", name: $0.name ?? "7-Eleven",
                                        latitude: c.latitude, longitude: c.longitude, openingHours: nil, branch: nil)
            }
    }

    // MARK: Tile cache

    struct TileKey: Hashable {
        let x: Int
        let y: Int

        var south: Double { Double(y) * SevenElevenService.tileSize }
        var west: Double { Double(x) * SevenElevenService.tileSize }
        var north: Double { south + SevenElevenService.tileSize }
        var east: Double { west + SevenElevenService.tileSize }
        var fileName: String { "\(x)_\(y).json" }

        func contains(_ c: CLLocationCoordinate2D) -> Bool {
            c.latitude >= south && c.latitude < north && c.longitude >= west && c.longitude < east
        }
    }

    static func tileKeys(for region: MKCoordinateRegion) -> [TileKey] {
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let y0 = Int(floor(south / tileSize)), y1 = Int(floor(north / tileSize))
        let x0 = Int(floor(west / tileSize)), x1 = Int(floor(east / tileSize))
        guard (y1 - y0 + 1) * (x1 - x0 + 1) <= maxTiles * 4 else {
            return Array(repeating: TileKey(x: 0, y: 0), count: maxTiles + 1) // "too many" sentinel
        }
        return (y0...y1).flatMap { y in (x0...x1).map { TileKey(x: $0, y: y) } }
    }

    private static func boundingBox(of tiles: [TileKey]) -> (south: Double, west: Double, north: Double, east: Double)? {
        guard !tiles.isEmpty else { return nil }
        return (tiles.map(\.south).min()!, tiles.map(\.west).min()!, tiles.map(\.north).max()!, tiles.map(\.east).max()!)
    }

    private static var cacheDirectory: URL {
        let dir = URL.cachesDirectory.appending(path: "seven-eleven", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Cached tiles are good for 30 days (stores rarely move).
    private static func cache(_ tile: TileKey) -> [ConvenienceStore]? {
        let url = cacheDirectory.appending(path: tile.fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 30 * 86_400,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([ConvenienceStore].self, from: data)
    }

    private static func store(_ stores: [ConvenienceStore], for tile: TileKey) {
        guard let data = try? JSONEncoder().encode(stores) else { return }
        try? data.write(to: cacheDirectory.appending(path: tile.fileName), options: .atomic)
    }

    /// Google Maps search for 7-Elevens around a point (app if installed, else web).
    @MainActor
    static func openInGoogleMaps(near c: CLLocationCoordinate2D) {
        if ExternalApps.hasGoogleMaps,
           let app = URL(string: "comgooglemaps://?q=7-Eleven&center=\(c.latitude),\(c.longitude)&zoom=16") {
            UIApplication.shared.open(app)
        } else if let web = URL(string: "https://www.google.com/maps/search/7-Eleven/@\(c.latitude),\(c.longitude),16z") {
            UIApplication.shared.open(web)
        }
    }
}

extension MKCoordinateRegion {
    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        abs(c.latitude - center.latitude) <= span.latitudeDelta / 2
            && abs(c.longitude - center.longitude) <= span.longitudeDelta / 2
    }
}

