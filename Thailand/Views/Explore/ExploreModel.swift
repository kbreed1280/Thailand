import Foundation
import CoreLocation
import Observation

/// State for the Explore tab: which segment, where to search around, and the results.
@MainActor
@Observable
final class ExploreModel {
    var segment: ExploreSegment = .eat
    var query = ""

    private(set) var results: [PlaceResult] = []
    private(set) var isLoading = false
    private(set) var originName = "you"
    private(set) var userLocation: CLLocation?
    private(set) var locationDenied = false
    private(set) var hasSearched = false

    /// Known city / area names are treated as "search around this place" rather than keywords.
    private var knownPlaces: [String] {
        StarterCity.allCases.map(\.rawValue) + StayGuide.areas.map(\.name)
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasSearched = true
        }

        let location = await LocationService.shared.currentLocation()
        userLocation = location
        locationDenied = LocationService.shared.isDenied
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var found: [PlaceResult]
        if trimmed.isEmpty {
            guard let location else {
                results = []
                return
            }
            originName = "you"
            found = await PlaceSearchService.nearby(segment, around: location.coordinate)
        } else if knownPlaces.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            found = await searchAround(placeNamed: trimmed)
        } else {
            originName = location == nil ? "Thailand" : "you"
            found = await PlaceSearchService.search(trimmed, segment: segment, around: location?.coordinate)
            if found.isEmpty {
                found = await searchAround(placeNamed: trimmed)
            }
        }

        if let location {
            found.sort { distance(to: $0, from: location) < distance(to: $1, from: location) }
        }
        results = found
    }

    /// Searches the segment's categories around a city/area ("Old City", "Ao Nang").
    func searchAround(area: StayArea) async {
        segment = .stay
        query = area.name
        isLoading = true
        originName = area.name
        results = await PlaceSearchService.nearby(.stay, around: CLLocationCoordinate2D(latitude: area.latitude, longitude: area.longitude), radius: 2_500)
        isLoading = false
        hasSearched = true
    }

    func distance(to place: PlaceResult) -> CLLocationDistance? {
        userLocation.map { distance(to: place, from: $0) }
    }

    private func distance(to place: PlaceResult, from location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }

    private func searchAround(placeNamed name: String) async -> [PlaceResult] {
        guard let place = await PlaceSearchService.locate(name) else { return [] }
        originName = place.name
        return await PlaceSearchService.nearby(segment, around: place.coordinate, radius: 3_000)
    }
}
