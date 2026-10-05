import CoreData
import CoreLocation
import Foundation
import MapKit

/// Hand-picked must-sees for a city (researched, with Wikipedia photos and locations), bundled
/// as JSON so they show on the map instantly and offline.
struct TopPick: Codable, Identifiable, Equatable {
    var name: String
    var category: String
    var tip: String
    var latitude: Double?
    var longitude: Double?
    var photo: String?
    var wikipedia: String?
    /// For places with no Wikipedia page: located with Apple Maps on first use.
    var query: String?

    var id: String { name }
    var spotCategory: SpotCategory { SpotCategory(rawValue: category) ?? .explore }
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var photoURL: URL? { photo.flatMap(URL.init(string:)) }

    /// As a map "discover" place (stable negative id so it never clashes with Wikipedia page ids).
    var landmark: Landmark? {
        guard let c = coordinate else { return nil }
        let id = -abs(name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } % 1_000_000_000) - 1
        return Landmark(id: id, title: name, summary: tip, shortDescription: spotCategory.title,
                        imageURL: photoURL, latitude: c.latitude, longitude: c.longitude)
    }
}

enum TopPicks {
    private struct File: Codable { var city: String; var places: [TopPick] }

    static let bangkok: [TopPick] = {
        guard let url = Bundle.main.url(forResource: "BangkokTopPicks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.places.map { pick in
            var p = pick
            if p.coordinate == nil, let saved = resolved[p.name] { p.latitude = saved.0; p.longitude = saved.1 }
            return p
        }
    }()

    private static let resolvedKey = "topPicksResolved"
    private static var resolved: [String: (Double, Double)] {
        (UserDefaults.standard.dictionary(forKey: resolvedKey) as? [String: [Double]] ?? [:])
            .compactMapValues { $0.count == 2 ? ($0[0], $0[1]) : nil }
    }

    /// Bangkok picks with a location, looking up the few without one in Apple Maps (once).
    @MainActor
    static func bangkokLocated() async -> [TopPick] {
        var stored = UserDefaults.standard.dictionary(forKey: resolvedKey) as? [String: [Double]] ?? [:]
        var out: [TopPick] = []
        for var pick in bangkok {
            if pick.coordinate == nil, let query = pick.query {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.region = MKCoordinateRegion(center: .init(latitude: 13.7563, longitude: 100.5018),
                                                    latitudinalMeters: 40_000, longitudinalMeters: 40_000)
                if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                    let c = item.placemark.coordinate
                    pick.latitude = c.latitude
                    pick.longitude = c.longitude
                    stored[pick.name] = [c.latitude, c.longitude]
                    if pick.photo == nil, let site = item.url,
                       let photo = await PlacePhotos.shared.photo(name: pick.name, coordinate: c, website: site) {
                        pick.photo = photo.absoluteString
                    }
                }
            }
            if pick.coordinate != nil { out.append(pick) }
        }
        UserDefaults.standard.set(stored, forKey: resolvedKey)
        return out
    }

    /// Saves every pick to Spots, in a "Bangkok Top Picks" list, with its tip and photo.
    @MainActor
    static func saveAll(_ picks: [TopPick], to trip: Trip, context: NSManagedObjectContext) -> SpotCollection {
        let list = trip.sortedCollections.first { $0.name == "Bangkok Top Picks" }
            ?? CollectionStore.create(name: "Bangkok Top Picks", emoji: "⭐️", kind: .city, in: trip, context: context)
        list.notes = "Bangkok's most popular sights, markets, food spots, rooftop bars and malls."
        for pick in picks {
            guard let spot = save(pick, to: trip, context: context) else { continue }
            CollectionStore.add(spot, to: list, note: pick.tip, context: context)
        }
        ItineraryStore(context: context).save()
        return list
    }

    @MainActor @discardableResult
    static func save(_ pick: TopPick, to trip: Trip, context: NSManagedObjectContext) -> Spot? {
        guard let c = pick.coordinate,
              let spot = SpotSaver.save(name: pick.name, coordinate: c, address: "", category: pick.spotCategory, context: context)
        else { return nil }
        spot.city = spot.city?.isEmpty == false ? spot.city : "Bangkok"
        // A source carrying the photo and the tip, so cards and pins show the picture.
        if !spot.sortedScoops.contains(where: { $0.source?.extractor == "top-picks" }) {
            let source = SpotSource(context: context)
            source.placeInSameStore(as: trip)
            source.uuid = UUID()
            source.urlString = pick.wikipedia ?? ""
            source.platformRaw = SourcePlatform.web.rawValue
            source.title = "Bangkok Top Picks"
            source.creator = "WanderHub"
            source.thumbnailURL = pick.photo ?? ""
            source.status = .ready
            source.extractor = "top-picks"
            source.createdAt = .now
            source.trip = trip
            let scoop = SpotScoop(context: context)
            scoop.placeInSameStore(as: trip)
            scoop.uuid = UUID()
            scoop.recommendation = pick.tip
            scoop.createdAt = .now
            scoop.spot = spot
            scoop.source = source
        }
        return spot
    }
}
