import CoreLocation
import Foundation

/// Photos of well-known places (temples, markets, landmarks) from Wikipedia's free API:
/// articles within 400 m of the spot whose title matches its name. Cached on disk.
actor PlacePhotos {
    static let shared = PlacePhotos()

    private var memory: [String: URL?] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private let defaultsKey = "placePhotoCache"

    func photo(name: String, coordinate: CLLocationCoordinate2D) async -> URL? {
        let key = String(format: "%@|%.4f,%.4f", name.lowercased(), coordinate.latitude, coordinate.longitude)
        if let hit = memory[key] { return hit }
        if let stored = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String])?[key] {
            let url = stored.isEmpty ? nil : URL(string: stored)
            memory[key] = url
            return url
        }
        if let running = inFlight[key] { return await running.value }
        let task = Task { await Self.lookup(name: name, coordinate: coordinate) }
        inFlight[key] = task
        let url = await task.value
        inFlight[key] = nil
        memory[key] = url
        var stored = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        stored[key] = url?.absoluteString ?? ""
        UserDefaults.standard.set(stored, forKey: defaultsKey)
        return url
    }

    private static func lookup(name: String, coordinate c: CLLocationCoordinate2D) async -> URL? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "generator", value: "geosearch"),
            .init(name: "ggscoord", value: "\(c.latitude)|\(c.longitude)"),
            .init(name: "ggsradius", value: "400"), .init(name: "ggslimit", value: "10"),
            .init(name: "prop", value: "pageimages"), .init(name: "piprop", value: "thumbnail"),
            .init(name: "pithumbsize", value: "400"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("WanderHub/1.0 (iOS travel app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return bestPhoto(in: data, for: name)
    }

    /// Pure: the thumbnail of the nearby article whose title best matches the spot (tested).
    static func bestPhoto(in data: Data, for name: String) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = (json["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] else { return nil }
        let candidates = pages.values.compactMap { page -> (Double, URL)? in
            guard let title = page["title"] as? String,
                  let source = (page["thumbnail"] as? [String: Any])?["source"] as? String,
                  let url = URL(string: source) else { return nil }
            let score = max(NameMatch.similarity(title, name), NameMatch.similarity(name, title))
            return score >= 0.6 ? (score, url) : nil
        }
        return candidates.max { $0.0 < $1.0 }?.1
    }
}
