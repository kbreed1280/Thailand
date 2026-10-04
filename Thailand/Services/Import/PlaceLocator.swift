import CoreLocation
import MapKit

/// Matches an extracted place name to a real place in Apple Maps (free, no key).
protocol PlaceLocating {
    func locate(_ place: ExtractedPlace, near area: TravelArea?, declared: CLLocationCoordinate2D?) async -> MKMapItem?
    func search(_ query: String, near area: TravelArea?) async -> [MKMapItem]
}

struct AppleMapsLocator: PlaceLocating {
    /// Thailand, for searches with no known area.
    static let thailand = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 13.0, longitude: 101.0),
                                             span: MKCoordinateSpan(latitudeDelta: 13, longitudeDelta: 8))

    /// Businesses/landmarks only, in a tight region: Apple Maps' Thailand results are excellent
    /// city-scoped but poor (roads, districts abroad) when searching the whole country with addresses.
    func search(_ query: String, near area: TravelArea?) async -> [MKMapItem] {
        if let area {
            return await search(query, in: MKCoordinateRegion(center: area.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000))
        }
        // No area: try Bangkok (most posts), then the whole country.
        let bangkok = await search(query, in: MKCoordinateRegion(center: TravelArea.all[0].coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000))
        if !bangkok.isEmpty { return bangkok }
        return await search(query, in: Self.thailand)
    }

    func search(_ query: String, in region: MKCoordinateRegion, types: MKLocalSearch.ResultType = .pointOfInterest) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = types
        request.region = region
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        // Stay in/near Thailand (a whole-country search can drift abroad).
        return items.filter { Self.thailand.contains($0.placemark.coordinate) }
    }

    func locate(_ place: ExtractedPlace, near area: TravelArea?, declared: CLLocationCoordinate2D?) async -> MKMapItem? {
        // 1. A pinned location (Google Maps link, page geo data): search right around it.
        if let declared {
            let nearby = await search(place.name, in: MKCoordinateRegion(center: declared, latitudinalMeters: 3_000, longitudinalMeters: 3_000))
            if let hit = Self.bestMatch(for: place.name, in: nearby, near: declared, strict: place.isGuess) { return hit }
        }
        // 2. The city the post or the place mentions, then Bangkok / all of Thailand.
        let region = TravelArea.detect(in: place.cityHint) ?? area
        var results = await search(place.name, near: region)
        if Self.bestMatch(for: place.name, in: results, near: declared ?? region?.coordinate, strict: place.isGuess) == nil, region != nil {
            results += await search(place.name, near: nil)
        }
        return Self.bestMatch(for: place.name, in: results, near: declared ?? region?.coordinate, strict: place.isGuess)
    }

    /// Picks the result whose name best matches, preferring ones near the expected spot.
    /// Returns nil when nothing is a convincing match (the spot is flagged "unplotted" instead).
    /// `strict` (for guesses): names must match both ways, so "Chao Phraya River" doesn't become
    /// "Four Seasons Hotel Bangkok at Chao Phraya River".
    static func bestMatch(for name: String, in items: [MKMapItem], near anchor: CLLocationCoordinate2D?, strict: Bool = false) -> MKMapItem? {
        let scored = items.map { item -> (MKMapItem, Double) in
            if strict { return (item, NameMatch.mutualSimilarity(name, item.name ?? "") - 0.17) } // needs ≥ ⅔ both ways
            var score = NameMatch.similarity(name, item.name ?? "")
            if let anchor {
                let d = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
                    .distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
                score += d < 2_000 ? 0.25 : d < 30_000 ? 0.1 : d > 300_000 ? -0.3 : 0
            }
            if item.pointOfInterestCategory != nil { score += 0.05 }
            return (item, score)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 else { return nil }
        return best.0
    }
}

/// Fuzzy name comparison that tolerates "Jay Fai" vs "Raan Jay Fai (ร้านเจ๊ไฝ)".
enum NameMatch {
    static func tokens(_ s: String) -> Set<String> {
        let stop: Set<String> = ["the", "a", "of", "at", "and", "restaurant", "cafe", "café", "bar", "raan", "ร้าน", "bangkok", "thailand"]
        return Set(s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stop.contains($0) })
    }

    /// "Night Market", "Thai Massage", "Bangkok Shopping Spree": activities, not a specific place.
    static func isGeneric(_ name: String) -> Bool {
        let generic: Set<String> = ["thai", "thailand", "night", "market", "markets", "massage", "cooking", "school", "class",
                                    "shopping", "spree", "boxing", "muay", "match", "street", "food", "river", "temple", "temples",
                                    "beach", "beaches", "island", "islands", "bar", "bars", "cafe", "cafes", "restaurant",
                                    "restaurants", "hotel", "spa", "mall", "rooftop", "tour", "cruise", "dinner", "sunset", "old", "town"]
        return tokens(name).subtracting(generic).isEmpty
    }

    /// 0–1: shared words over the *longer* name's words, so extra words on either side lower the score.
    static func mutualSimilarity(_ a: String, _ b: String) -> Double {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        return Double(ta.intersection(tb).count) / Double(max(ta.count, tb.count))
    }

    /// 0–1: share of the shorter name's words found in the other (plus a bonus for containment).
    static func similarity(_ a: String, _ b: String) -> Double {
        let ta = tokens(a), tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let overlap = Double(ta.intersection(tb).count) / Double(min(ta.count, tb.count))
        let la = a.lowercased(), lb = b.lowercased()
        return min(1, overlap + ((la.contains(lb) || lb.contains(la)) ? 0.2 : 0))
    }
}
