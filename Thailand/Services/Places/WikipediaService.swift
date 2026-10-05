import Foundation
import CoreLocation

/// A nearby landmark from Wikipedia's GeoSearch.
struct Landmark: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let summary: String
    let shortDescription: String?
    let imageURL: URL?
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var articleURL: URL? { URL(string: "https://en.wikipedia.org/?curid=\(id)") }

    func distance(from location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    var asPlace: PlaceResult {
        PlaceResult(name: title, address: shortDescription ?? "", latitude: latitude, longitude: longitude,
                    phone: nil, url: articleURL, categoryName: "Landmark")
    }
}

/// Wikipedia GeoSearch (`generator=geosearch` + `pageimages|extracts`) within ~5 km.
/// The last results are cached on disk so the Nearby tab still shows something offline.
enum WikipediaService {
    private static let userAgent = "ThailandTripApp/1.0 (https://github.com/kbreed1280/Thailand)"

    private static var cacheURL: URL {
        URL.cachesDirectory.appending(path: "nearby-landmarks.json")
    }

    static func landmarks(near coordinate: CLLocationCoordinate2D, radius: Int = 5_000, limit: Int = 20,
                          remember: Bool = true) async throws -> [Landmark] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "geosearch"),
            URLQueryItem(name: "ggscoord", value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            URLQueryItem(name: "ggsradius", value: "\(min(radius, 10_000))"),
            URLQueryItem(name: "ggslimit", value: "\(min(limit, 50))"),
            URLQueryItem(name: "prop", value: "coordinates|pageimages|extracts|description"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "640"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exsentences", value: "3"),
            URLQueryItem(name: "exlimit", value: "20")
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let landmarks = (decoded.query?.pages ?? []).compactMap { page -> Landmark? in
            guard let point = page.coordinates?.first else { return nil }
            return Landmark(
                id: page.pageid,
                title: page.title,
                summary: page.extract ?? "",
                shortDescription: page.description,
                imageURL: page.thumbnail.flatMap { URL(string: $0.source) },
                latitude: point.lat,
                longitude: point.lon
            )
        }
        .sorted { $0.distance(from: origin) < $1.distance(from: origin) }

        if remember, let encoded = try? JSONEncoder().encode(landmarks) {
            try? encoded.write(to: cacheURL, options: .atomic)
        }
        return landmarks
    }

    static func cachedLandmarks() -> [Landmark] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        return (try? JSONDecoder().decode([Landmark].self, from: data)) ?? []
    }

    // MARK: Response

    private struct Response: Decodable {
        let query: Query?
    }

    private struct Query: Decodable {
        let pages: [Page]
    }

    private struct Page: Decodable {
        let pageid: Int
        let title: String
        let extract: String?
        let description: String?
        let thumbnail: Thumbnail?
        let coordinates: [Coordinate]?
    }

    private struct Thumbnail: Decodable {
        let source: String
    }

    private struct Coordinate: Decodable {
        let lat: Double
        let lon: Double
    }
}
