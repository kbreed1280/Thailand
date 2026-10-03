import Foundation
import MapKit

/// A search result reduced to plain values (safe to keep in view state).
struct PlaceResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let phone: String?
    let url: URL?
    let categoryName: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Address and place lookups using MapKit search (works for Thai and English queries).
enum PlaceLookup {
    /// Thailand, roughly — biases results when no better region is known.
    static let thailandRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 13.0, longitude: 101.0),
        span: MKCoordinateSpan(latitudeDelta: 16, longitudeDelta: 12)
    )

    static func search(_ query: String, near region: MKCoordinateRegion? = nil) async -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = region ?? thailandRegion
        request.resultTypes = [.pointOfInterest, .address]
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.map(result(from:))
    }

    static func result(from item: MKMapItem) -> PlaceResult {
        let coordinate = item.placemark.coordinate
        return PlaceResult(
            name: item.name ?? "Unnamed place",
            address: formattedAddress(item.placemark),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            phone: item.phoneNumber,
            url: item.url,
            categoryName: item.pointOfInterestCategory.map(categoryTitle)
        )
    }

    static func formattedAddress(_ placemark: MKPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, placemark.subLocality ?? "", placemark.locality ?? "", placemark.administrativeArea ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func categoryTitle(_ category: MKPointOfInterestCategory) -> String {
        let raw = category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
        // "NationalPark" -> "National Park"
        return raw.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
    }

    /// Opens Apple Maps with walking directions to a coordinate.
    static func appleMapsURL(to coordinate: CLLocationCoordinate2D, name: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "dirflg", value: "w")
        ]
        return components?.url
    }
}
