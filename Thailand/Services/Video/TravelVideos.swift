import CoreData
import CoreLocation
import Foundation
import MapKit

/// Caption, creator and thumbnail for a shared video (TikTok oEmbed; no key needed).
struct VideoInfo: Codable, Equatable {
    var title: String
    var author: String?
    var thumbnailURL: URL?
    var canonicalURL: URL
}

/// Areas of Thailand videos get filed under, with words that point to them in captions.
struct TravelArea: Identifiable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    let aliases: [String]
    var id: String { name }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    static let elsewhere = "Elsewhere in Thailand"

    static let all: [TravelArea] = [
        .init(name: "Bangkok", latitude: 13.7563, longitude: 100.5018,
              aliases: ["bangkok", "bkk", "krung thep", "sukhumvit", "silom", "khao san", "khaosan", "siam", "chinatown", "yaowarat", "thonglor", "ari", "chatuchak", "ratchada", "jodd fairs", "iconsiam"]),
        .init(name: "Ayutthaya", latitude: 14.3532, longitude: 100.5689, aliases: ["ayutthaya", "ayuthaya"]),
        .init(name: "Kanchanaburi", latitude: 14.0228, longitude: 99.5328, aliases: ["kanchanaburi", "erawan", "river kwai"]),
        .init(name: "Pattaya", latitude: 12.9236, longitude: 100.8825, aliases: ["pattaya", "jomtien"]),
        .init(name: "Hua Hin", latitude: 12.5684, longitude: 99.9577, aliases: ["hua hin", "huahin"]),
        .init(name: "Chiang Mai", latitude: 18.7883, longitude: 98.9853, aliases: ["chiang mai", "chiangmai", "nimman", "doi suthep", "old city cm", "cnx"]),
        .init(name: "Chiang Rai", latitude: 19.9105, longitude: 99.8406, aliases: ["chiang rai", "chiangrai", "white temple", "blue temple"]),
        .init(name: "Pai", latitude: 19.3583, longitude: 98.4405, aliases: ["pai canyon", " in pai", "pai thailand", "#pai"]),
        .init(name: "Sukhothai", latitude: 17.0078, longitude: 99.8230, aliases: ["sukhothai"]),
        .init(name: "Phuket", latitude: 7.8804, longitude: 98.3923, aliases: ["phuket", "patong", "kata", "karon", "old town phuket"]),
        .init(name: "Krabi / Ao Nang", latitude: 8.0355, longitude: 98.8199, aliases: ["krabi", "ao nang", "aonang", "railay", "tonsai", "hong island"]),
        .init(name: "Koh Phi Phi", latitude: 7.7407, longitude: 98.7784, aliases: ["phi phi", "maya bay"]),
        .init(name: "Koh Lanta", latitude: 7.6247, longitude: 99.0791, aliases: ["koh lanta", "ko lanta", "lanta"]),
        .init(name: "Koh Samui", latitude: 9.5120, longitude: 100.0136, aliases: ["samui", "chaweng", "lamai", "fisherman's village"]),
        .init(name: "Koh Phangan", latitude: 9.7319, longitude: 100.0136, aliases: ["phangan", "pha ngan", "full moon party", "haad rin"]),
        .init(name: "Koh Tao", latitude: 10.0956, longitude: 99.8404, aliases: ["koh tao", "ko tao"]),
        .init(name: "Koh Chang", latitude: 12.0517, longitude: 102.3290, aliases: ["koh chang", "ko chang"]),
        .init(name: "Koh Lipe", latitude: 6.4886, longitude: 99.3036, aliases: ["koh lipe", "ko lipe", "lipe"]),
    ]

    static func named(_ name: String) -> TravelArea? { all.first { $0.name == name } }

    /// The area a caption talks about, by the most specific (longest) alias found.
    static func detect(in text: String) -> TravelArea? {
        let lower = " " + text.lowercased() + " "
        return all.compactMap { area -> (TravelArea, Int)? in
            let hits = area.aliases.filter { lower.contains($0) }
            return hits.max(by: { $0.count < $1.count }).map { (area, $0.count) }
        }
        .max { $0.1 < $1.1 }?.0
    }

    /// Nearest area to a point, if within ~80 km.
    static func nearest(to coordinate: CLLocationCoordinate2D) -> TravelArea? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let best = all.min(by: { $0.location.distance(from: here) < $1.location.distance(from: here) }),
              best.location.distance(from: here) < 80_000 else { return nil }
        return best
    }
}

enum TravelVideos {
    // MARK: Metadata

    private static var cache: [URL: VideoInfo] = [:]

    static func isVideoLink(_ link: String?) -> Bool {
        guard let link, let host = URL(string: link)?.host?.lowercased() else { return false }
        return ["tiktok.com", "youtube.com", "youtu.be", "instagram.com"].contains { host.hasSuffix($0) }
    }

    /// Caption, creator and thumbnail. Short links (vm.tiktok.com) are expanded first.
    static func info(for url: URL) async -> VideoInfo? {
        if let hit = cache[url] { return hit }
        var target = url
        if let host = url.host, host.hasPrefix("vm.") || host.hasPrefix("vt.") || host == "tiktok.com" {
            target = await expand(url) ?? url
        }
        let isYouTube = target.host?.contains("youtu") == true
        var components = URLComponents(string: isYouTube ? "https://www.youtube.com/oembed" : "https://www.tiktok.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: target.absoluteString), URLQueryItem(name: "format", value: "json")]
        struct OEmbed: Decodable {
            let title: String?
            let author_name: String?
            let author_unique_id: String?
            let thumbnail_url: String?
        }
        guard let endpoint = components.url,
              let (data, response) = try? await URLSession.shared.data(from: endpoint),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONDecoder().decode(OEmbed.self, from: data) else { return nil }
        let info = VideoInfo(
            title: (o.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            author: o.author_unique_id.map { "@\($0)" } ?? o.author_name,
            thumbnailURL: o.thumbnail_url.flatMap(URL.init(string:)),
            canonicalURL: target
        )
        cache[url] = info
        return info
    }

    private static func expand(_ url: URL) async -> URL? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return response.url.map { URL(string: $0.absoluteString.components(separatedBy: "?").first ?? $0.absoluteString) ?? $0 }
    }

    // MARK: Finding the place

    /// Apple Maps places matching what the video is about, near its area (or anywhere in Thailand).
    static func suggestPlaces(for text: String, area: TravelArea?) async -> [MKMapItem] {
        let region = area.map { MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000) }
            ?? MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 13.0, longitude: 101.0),
                                  span: MKCoordinateSpan(latitudeDelta: 13, longitudeDelta: 8))
        var results: [MKMapItem] = []
        for query in candidateQueries(from: text).prefix(4) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            request.resultTypes = .pointOfInterest
            if let found = try? await MKLocalSearch(request: request).start().mapItems {
                for item in found.prefix(4) where !results.contains(where: { $0.name == item.name })
                    && (area == nil || region.contains(item.placemark.coordinate)) {
                    results.append(item)
                }
            }
            if results.count >= 6 { break }
        }
        return results
    }

    /// Search phrases from a caption: hashtags split into words ("#joddfairs" → "jodd fairs" isn't
    /// possible, but "#JoddFairs" → "Jodd Fairs"), then the caption itself without tags/emoji.
    static func candidateQueries(from text: String) -> [String] {
        let tags = text.matches(of: /#(\w+)/).map { String($0.1) }
            .filter { !["fyp", "foryou", "foryoupage", "thailand", "travel", "thailandtravel", "traveltiktok", "bangkok", "viral"].contains($0.lowercased()) }
            .map { $0.replacing(/([a-z])([A-Z])/) { "\($0.1) \($0.2)" } }
        let plain = text
            .replacing(/#\w+/, with: "")
            .replacing(/@\w+/, with: "")
            .unicodeScalars.filter { $0.properties.isEmoji == false || $0.isASCII }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = plain.split(whereSeparator: \.isNewline).first.map(String.init) ?? plain
        var queries = tags
        if !firstLine.isEmpty { queries.insert(String(firstLine.prefix(80)), at: 0) }
        return queries.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    // MARK: Saving to the trip

    /// Saved video items on a trip (wish list or days).
    static func saved(in trip: Trip) -> [Item] {
        trip.allItems.filter { isVideoLink($0.link) }
    }

    /// Area a saved video belongs to: the "Area:" line we wrote, else nearest to its pin.
    static func area(of item: Item) -> String {
        if let line = (item.notes ?? "").split(separator: "\n").first(where: { $0.hasPrefix("Area: ") }) {
            return String(line.dropFirst(6))
        }
        if let c = item.coordinate, let area = TravelArea.nearest(to: c) { return area.name }
        return TravelArea.elsewhere
    }

    /// Adds the video to the trip's wish list: pinned at a place, or filed under an area.
    @discardableResult
    static func save(link: URL, info: VideoInfo?, place: MKMapItem?, area: String, to trip: Trip,
                     context: NSManagedObjectContext) -> Item {
        let caption = info?.title ?? ""
        let shortCaption = caption.split(whereSeparator: \.isNewline).first.map { String($0.prefix(60)) } ?? ""
        let title = place?.name ?? (shortCaption.isEmpty ? "TikTok: \(area)" : shortCaption)
        let category: ItemCategory = {
            switch place?.pointOfInterestCategory {
            case .restaurant?, .cafe?, .bakery?, .brewery?, .winery?, .foodMarket?: .meal
            case .hotel?: .hotel
            default: .place
            }
        }()
        var notes = "🎬 TikTok\(info?.author.map { " · \($0)" } ?? "")"
        if !caption.isEmpty { notes += "\n\(caption)" }
        notes += "\nArea: \(area)"

        let item = ItineraryStore(context: context).addItem(
            title: title, category: category, to: nil, in: trip,
            address: place?.placemark.title ?? area,
            coordinate: place?.placemark.coordinate,
            notes: notes
        )
        item.link = (info?.canonicalURL ?? link).absoluteString
        ItineraryStore(context: context).save()
        return item
    }
}
