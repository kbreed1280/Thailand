import CoreLocation
import Foundation
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A place found for a destination (Apple Maps), not yet saved.
struct PlaceIdea: Identifiable {
    let id = UUID()
    var name: String
    var coordinate: CLLocationCoordinate2D
    var category: SpotCategory
    var address: String
    var url: URL?
}

/// Finds popular places around any destination with Apple Maps: the "Top Picks" map layer for
/// trips outside Bangkok, and the raw ideas the trip builder plans from.
enum DestinationIdeas {
    /// What a first-time visitor usually wants, as Apple Maps searches.
    static let starterSearches: [(query: String, category: SpotCategory)] = [
        ("top attractions", .explore), ("landmark", .explore), ("museum", .explore),
        ("popular restaurant", .eat), ("local food", .eat), ("coffee", .brew),
        ("cocktail bar", .sip), ("market", .go), ("park", .vibe), ("hotel", .stay),
    ]

    /// Up to `perQuery` places per search within `radius` of `center`, de-duplicated by name and spot.
    static func find(_ searches: [(query: String, category: SpotCategory?)], around center: CLLocationCoordinate2D,
                     radius: CLLocationDistance = 12_000, perQuery: Int = 4) async -> [PlaceIdea] {
        var ideas: [PlaceIdea] = []
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        for search in searches {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = search.query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            var added = 0
            for item in items where added < perQuery {
                guard let name = item.name, let loc = item.placemark.location, loc.distance(from: here) <= radius else { continue }
                let duplicate = ideas.contains { idea in
                    idea.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                        || AutoPlanner.distance(idea.coordinate, loc.coordinate) < 40
                }
                guard !duplicate else { continue }
                ideas.append(PlaceIdea(name: name, coordinate: loc.coordinate,
                                       category: search.category ?? SpotCategory(poi: item.pointOfInterestCategory),
                                       address: item.placemark.title ?? "", url: item.url))
                added += 1
            }
        }
        return ideas
    }

    // MARK: Top Picks for any city

    private static func cacheKey(_ c: CLLocationCoordinate2D) -> String {
        String(format: "destinationPicks.%.2f,%.2f", c.latitude, c.longitude)
    }

    /// Top Picks around a trip's destination (cached for a week so the map loads instantly).
    @MainActor
    static func topPicks(around center: CLLocationCoordinate2D, city: String) async -> [TopPick] {
        let key = cacheKey(center)
        if let data = UserDefaults.standard.data(forKey: key),
           let cached = try? JSONDecoder().decode(CachedPicks.self, from: data),
           Date().timeIntervalSince(cached.date) < 7 * 86_400 {
            return cached.picks
        }
        let ideas = await find(starterSearches.map { ($0.query, Optional($0.category)) }, around: center, perQuery: 3)
        var picks: [TopPick] = []
        for idea in ideas {
            var pick = TopPick(name: idea.name, category: idea.category.rawValue, tip: idea.address,
                               latitude: idea.coordinate.latitude, longitude: idea.coordinate.longitude)
            if let site = idea.url, picks.count < 20,
               let photo = await PlacePhotos.shared.photo(name: idea.name, coordinate: idea.coordinate, website: site) {
                pick.photo = photo.absoluteString
            }
            picks.append(pick)
        }
        if let data = try? JSONEncoder().encode(CachedPicks(date: .now, city: city, picks: picks)) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return picks
    }

    private struct CachedPicks: Codable { var date: Date; var city: String; var picks: [TopPick] }

    // MARK: Turning wishes into searches

    /// "ramen, jazz bars and art museums" → Apple Maps searches. Uses Apple Intelligence on
    /// devices that have it, and simple phrase splitting everywhere else. Returns whether AI was used.
    static func searches(for wishes: String, destination: String, vibe: AutoPlanner.Vibe) async -> (searches: [String], usedAI: Bool) {
        let trimmed = wishes.trimmingCharacters(in: .whitespacesAndNewlines)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), !trimmed.isEmpty, case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession(instructions: """
                You help plan trips. Turn a traveler's wishes into short searches for places on Apple Maps, \
                like "ramen", "jazz bar", "art museum", "rooftop bar", "night market". \
                Never include city names. Give 6 to 10 searches, most important first.
                """)
            let prompt = "Destination: \(destination.isEmpty ? "unknown" : destination). Trip style: \(vibe.title). Wishes: \(trimmed)"
            if let response = try? await session.respond(to: prompt, generating: TripSearchPlan.self) {
                let cleaned = clean(response.content.searches)
                if !cleaned.isEmpty { return (cleaned, true) }
            }
        }
        #endif
        return (clean(phrases(in: trimmed) + vibe.fillQueries), false)
    }

    /// Splits free text into short phrases: "ramen, jazz bars and museums" → ["ramen", "jazz bars", "museums"].
    static func phrases(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: "&", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .map { phrase in
                // Drop filler like "i love", "lots of", "some".
                var p = phrase
                for filler in ["i love ", "i like ", "we love ", "we like ", "lots of ", "a lot of ", "some ", "good ", "great ", "the best "] where p.hasPrefix(filler) {
                    p.removeFirst(filler.count)
                }
                return p
            }
            .filter { $0.count >= 3 && $0.split(separator: " ").count <= 4 }
    }

    static func clean(_ searches: [String]) -> [String] {
        var seen = Set<String>()
        return searches
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(10).map { $0 }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct TripSearchPlan {
    @Guide(description: "6 to 10 short Apple Maps searches for kinds of places this traveler would love, without city names")
    var searches: [String]
}
#endif
