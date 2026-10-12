import CoreData
import CoreLocation
import MapKit

/// Re-checks where saved spots are pinned: looks each one up on Apple Maps near the trip (and the
/// spot's city), and moves the pin when a business with the same name is found somewhere else.
/// Spots it can't confirm are reported so you can fix them by hand.
@MainActor
enum LocationChecker {
    struct Result {
        var checked = 0
        var moved: [String] = []
        var unconfirmed: [String] = []
    }

    /// A different spot this far away counts as a wrong pin.
    static let moveThreshold: CLLocationDistance = 150
    /// Names must be at least this similar to count as the same business.
    static let minSimilarity = 0.6

    static func check(_ spots: [Spot], trip: Trip) async -> Result {
        var result = Result()
        for spot in spots {
            result.checked += 1
            guard let match = await bestMatch(for: spot, trip: trip) else {
                result.unconfirmed.append(spot.displayName)
                continue
            }
            let here = spot.coordinate
            let there = match.placemark.coordinate
            let off = here.map { AutoPlanner.distance($0, there) } ?? .infinity
            if off > moveThreshold || (spot.appleMapsID ?? "").isEmpty {
                let keepName = spot.displayName
                spot.apply(match)
                spot.name = keepName
                if off > moveThreshold { result.moved.append(keepName) }
            }
        }
        return result
    }

    /// The Apple Maps business that best matches the spot's name, near the spot or the trip.
    static func bestMatch(for spot: Spot, trip: Trip) async -> MKMapItem? {
        let name = spot.displayName
        var centers: [CLLocationCoordinate2D] = []
        if let c = spot.coordinate { centers.append(c) }
        if let d = trip.destinationCoordinate { centers.append(d) }
        guard !centers.isEmpty else { return nil }

        var best: (item: MKMapItem, score: Double)?
        for center in centers {
            for query in [name, [name, spot.city ?? ""].filter { !$0.isEmpty }.joined(separator: " ")] {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = query
                request.resultTypes = .pointOfInterest
                request.region = MKCoordinateRegion(center: center, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
                let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
                for item in items.prefix(8) {
                    guard let itemName = item.name else { continue }
                    let score = NameMatch.similarity(name, itemName)
                    guard score >= minSimilarity else { continue }
                    // Prefer the closest of equally good matches to where it's pinned now.
                    let near = spot.coordinate.map { AutoPlanner.distance($0, item.placemark.coordinate) } ?? 0
                    let adjusted = score - min(near / 200_000, 0.1)
                    if best == nil || adjusted > best!.score { best = (item, adjusted) }
                }
            }
            if let best, best.score >= 0.95 { break }
        }
        return best?.item
    }
}
