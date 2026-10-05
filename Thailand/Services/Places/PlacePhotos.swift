import CoreLocation
import Foundation

/// Photos of places: Wikipedia (articles within 400 m whose title matches the name) for
/// landmarks, then the place's own website preview image (og:image), which most hotels,
/// restaurants and bars have. Cached on disk.
actor PlacePhotos {
    static let shared = PlacePhotos()

    private var memory: [String: URL?] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private let defaultsKey = "placePhotoCache"

    func photo(name: String, coordinate: CLLocationCoordinate2D, website: URL? = nil) async -> URL? {
        let key = String(format: "v2|%@|%.4f,%.4f|%@", name.lowercased(), coordinate.latitude, coordinate.longitude, website?.host() ?? "")
        if let hit = memory[key] { return hit }
        if let stored = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String])?[key] {
            let url = stored.isEmpty ? nil : URL(string: stored)
            memory[key] = url
            return url
        }
        if let running = inFlight[key] { return await running.value }
        let task = Task<URL?, Never> {
            if let wiki = await Self.lookup(name: name, coordinate: coordinate) { return wiki }
            if let website { return await Self.websitePhoto(website) }
            return nil
        }
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

    /// The preview image a website shares (og:image / twitter:image), e.g. a hotel's hero photo.
    private static func websitePhoto(_ site: URL) async -> URL? {
        guard let html = await LinkReader.fetchHTML(site) else { return nil }
        let og = LinkReader.parseOpenGraph(html)
        guard let raw = og["og:image"] ?? og["og:image:url"] ?? og["twitter:image"], !raw.isEmpty else { return nil }
        let url = URL(string: raw, relativeTo: site)?.absoluteURL
        // Skip logos and icons; we want a photo.
        if let path = url?.path.lowercased(), ["logo", "icon", "favicon", ".svg"].contains(where: path.contains) { return nil }
        return url
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
