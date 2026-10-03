import Foundation
import MapKit

enum ExploreSegment: String, CaseIterable, Identifiable {
    case eat = "Eat"
    case stay = "Stay"
    case see = "See"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .eat: "fork.knife"
        case .stay: "bed.double.fill"
        case .see: "binoculars.fill"
        }
    }

    var categories: [MKPointOfInterestCategory] {
        switch self {
        case .eat: [.restaurant, .cafe, .bakery, .nightlife, .foodMarket]
        case .stay: [.hotel]
        case .see: [.museum, .park, .beach, .landmark, .nationalPark]
        }
    }

    var itemCategory: ItemCategory {
        switch self {
        case .eat: .meal
        case .stay: .hotel
        case .see: .place
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .eat: "Search food or a city (e.g. khao soi, Chiang Mai)"
        case .stay: "Search hotels or a city"
        case .see: "Search sights or a city"
        }
    }
}

/// Finds places to eat, stay and see near the user or near a searched city.
enum PlaceSearchService {
    /// Points of interest of the segment's categories around a coordinate.
    static func nearby(_ segment: ExploreSegment, around center: CLLocationCoordinate2D, radius: CLLocationDistance = 2_000) async -> [PlaceResult] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: segment.categories)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.map(PlaceLookup.result(from:))
    }

    /// Free-text search ("khao soi", "rooftop bar") filtered to the segment, near `center`.
    static func search(_ query: String, segment: ExploreSegment, around center: CLLocationCoordinate2D?) async -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: segment.categories)
        if let center {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        } else {
            request.region = PlaceLookup.thailandRegion
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.map(PlaceLookup.result(from:))
    }

    /// Looks up a city or area name ("Chiang Mai", "Ao Nang") and returns its center.
    static func locate(_ placeName: String) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = placeName
        request.resultTypes = .address
        request.region = PlaceLookup.thailandRegion
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        return (item.name ?? placeName, item.placemark.coordinate)
    }
}
