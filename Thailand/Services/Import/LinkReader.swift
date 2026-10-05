import CoreLocation
import Foundation

/// Everything we could read about a shared link (never the video itself).
struct LinkContent: Equatable {
    var url: URL?
    var platform: SourcePlatform
    var title: String = ""
    var creator: String = ""
    var thumbnailURL: URL?
    /// Caption, description and any page/screenshot text: what the place extractor reads.
    var text: String = ""
    /// Places the page itself declares (schema.org JSON-LD, Google Maps links): high confidence.
    var declaredPlaces: [DeclaredPlace] = []

    struct DeclaredPlace: Equatable {
        var name: String
        var address: String?
        var coordinate: CLLocationCoordinate2D?

        static func == (a: Self, b: Self) -> Bool {
            a.name == b.name && a.address == b.address
                && a.coordinate?.latitude == b.coordinate?.latitude && a.coordinate?.longitude == b.coordinate?.longitude
        }
    }
}

/// Fetches captions/metadata per platform. Only public, documented endpoints and page metadata:
/// TikTok & YouTube oEmbed, Open Graph tags, schema.org JSON-LD, and Google Maps link structure.
enum LinkReader {
    static var session: URLSession = .shared

    static func read(_ url: URL, extraText: String? = nil) async -> LinkContent {
        var target = url
        if isShortLink(url), let expanded = await expand(url) { target = expanded }
        let platform = SourcePlatform(url: target)
        var content = LinkContent(url: target, platform: platform)

        switch platform {
        case .googleMaps:
            if let place = parseGoogleMaps(target) { content.declaredPlaces = [place]; content.title = place.name }
        case .tiktok, .youtube:
            // TikTok's oEmbed rejects photo slideshows (/photo/<id>) but accepts the same id as /video/<id>.
            var o = await oEmbed(target, platform: platform)
            if o == nil, let videoURL = tiktokVideoURL(forPhoto: target) { o = await oEmbed(videoURL, platform: platform) }
            if let o {
                content.title = o.title
                content.creator = o.author
                content.thumbnailURL = o.thumbnail
                content.text = o.title
            }
            // The creator's location tag (TikTok "poi"): a specific place becomes a declared place;
            // an island / city only narrows where we search.
            if platform == .tiktok, let page = await fetchHTML(target), let poi = parseTikTokPOI(page) {
                content.text = [content.text, "Location: \(poi.name), \(poi.address)"].filter { !$0.isEmpty }.joined(separator: "\n")
                if !poi.isArea {
                    content.declaredPlaces.append(.init(name: poi.name, address: poi.address, coordinate: nil))
                }
            }
            if platform == .youtube, let page = await fetchHTML(target) {
                // YouTube's description holds the place list; it's in the page's meta description.
                content.text = [content.text, parseOpenGraph(page)["og:description"] ?? ""].joined(separator: "\n")
            }
        case .instagram, .web, .screenshot:
            if let page = await fetchHTML(target) {
                let og = parseOpenGraph(page)
                content.title = og["og:title"] ?? parseTitle(page) ?? ""
                content.thumbnailURL = og["og:image"].flatMap(URL.init(string:))
                content.creator = og["og:site_name"] ?? ""
                content.declaredPlaces = parseJSONLDPlaces(page)
                let description = og["og:description"] ?? og["description"] ?? ""
                content.text = [content.title, description, platform == .web ? articleText(page, limit: 6_000) : ""]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
        if let extraText, !extraText.isEmpty {
            content.text = [content.text, extraText].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return content
    }

    // MARK: Network

    static func isShortLink(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return ["vm.tiktok.com", "vt.tiktok.com", "maps.app.goo.gl", "goo.gl", "youtu.be", "instagr.am"].contains(host)
            || (host == "tiktok.com" && url.path.hasPrefix("/t/"))
    }

    private static func expand(_ url: URL) async -> URL? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await session.data(for: request) else { return nil }
        return response.url
    }

    private static func fetchHTML(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        // Modern pages put megabytes of code before the content; read enough to reach it.
        return String(decoding: data.prefix(4_000_000), as: UTF8.self)
    }

    struct OEmbed { var title: String; var author: String; var thumbnail: URL? }

    private static func oEmbed(_ url: URL, platform: SourcePlatform) async -> OEmbed? {
        let endpoint = platform == .youtube ? "https://www.youtube.com/oembed" : "https://www.tiktok.com/oembed"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [.init(name: "url", value: url.absoluteString), .init(name: "format", value: "json")]
        guard let request = components.url,
              let (data, response) = try? await session.data(from: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseOEmbed(data)
    }

    // MARK: Parsing (pure, tested)

    struct TikTokPOI: Equatable {
        var name: String
        var address: String
        var city: String
        var kind: String
        /// Islands, cities, districts…: where the post is, not a place to pin.
        var isArea: Bool {
            let areaKinds = ["island", "city", "town", "province", "district", "region", "country", "state", "neighborhood",
                             "neighbourhood", "village", "administrative"]
            return areaKinds.contains { kind.lowercased().contains($0) }
                || NameMatch.similarity(name, city) >= 0.8
        }
    }

    /// The `"poi":{…}` object in a TikTok page's embedded JSON.
    static func parseTikTokPOI(_ html: String) -> TikTokPOI? {
        guard let start = html.range(of: "\"poi\":{")?.upperBound else { return nil }
        // Walk to the matching brace (strings may contain braces, so track quotes).
        var depth = 1, inString = false, escaped = false
        var end = start
        var i = start
        while i < html.endIndex, depth > 0 {
            let ch = html[i]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "\"" { inString.toggle() }
            else if !inString { if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1 } }
            end = i
            i = html.index(after: i)
        }
        guard depth == 0 else { return nil }
        let json = "{" + html[start..<end] + "}"
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let name = object["name"] as? String, !name.isEmpty else { return nil }
        return TikTokPOI(name: name, address: object["address"] as? String ?? "", city: object["city"] as? String ?? "",
                         kind: [object["ttTypeNameTiny"], object["ttTypeNameMedium"]].compactMap { $0 as? String }.joined(separator: " "))
    }

    /// https://www.tiktok.com/@user/photo/123?x → https://www.tiktok.com/@user/video/123
    static func tiktokVideoURL(forPhoto url: URL) -> URL? {
        guard url.host()?.hasSuffix("tiktok.com") == true, url.path.contains("/photo/"),
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        c.path = c.path.replacingOccurrences(of: "/photo/", with: "/video/")
        c.query = nil
        return c.url
    }

    static func parseOEmbed(_ data: Data) -> OEmbed? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let author = (json["author_unique_id"] as? String).map { "@\($0)" } ?? (json["author_name"] as? String) ?? ""
        return OEmbed(title: (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                      author: author,
                      thumbnail: (json["thumbnail_url"] as? String).flatMap(URL.init(string:)))
    }

    /// Place from a Google Maps link: /maps/place/<Name>/@lat,lon…, !3d<lat>!4d<lon>, or ?q=…
    static func parseGoogleMaps(_ url: URL) -> LinkContent.DeclaredPlace? {
        let s = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        var name: String?
        if let m = s.firstMatch(of: /\/maps\/place\/([^\/@?]+)/) {
            name = String(m.1).replacingOccurrences(of: "+", with: " ")
        } else if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "q" || $0.name == "query" })?.value {
            name = q.replacingOccurrences(of: "+", with: " ")
        }
        var coordinate: CLLocationCoordinate2D?
        if let m = s.firstMatch(of: /!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/), let lat = Double(m.1), let lon = Double(m.2) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon) // the pin itself
        } else if let m = s.firstMatch(of: /@(-?\d+\.\d+),(-?\d+\.\d+)/), let lat = Double(m.1), let lon = Double(m.2) {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon) // map center, close enough
        }
        // "?q=13.75,100.49" is a bare coordinate, not a name.
        if let n = name, let m = n.wholeMatch(of: /\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*/), let lat = Double(m.1), let lon = Double(m.2) {
            return LinkContent.DeclaredPlace(name: "Pinned location", address: nil,
                                             coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        guard let name, !name.isEmpty else { return nil }
        return LinkContent.DeclaredPlace(name: name, address: nil, coordinate: coordinate)
    }

    /// <meta property="og:…" content="…"> and <meta name="description" …>.
    static func parseOpenGraph(_ html: String) -> [String: String] {
        var result: [String: String] = [:]
        for m in html.matches(of: /<meta\s[^>]*>/.ignoresCase()) {
            let tag = String(m.0)
            guard let key = attribute("property", in: tag) ?? attribute("name", in: tag),
                  let value = attribute("content", in: tag) else { continue }
            let k = key.lowercased()
            if result[k] == nil { result[k] = decodeEntities(value) }
        }
        return result
    }

    static func parseTitle(_ html: String) -> String? {
        html.firstMatch(of: /<title[^>]*>([^<]*)<\/title>/.ignoresCase()).map { decodeEntities(String($0.1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// schema.org Restaurant / LocalBusiness / Place / TouristAttraction objects in JSON-LD.
    static func parseJSONLDPlaces(_ html: String) -> [LinkContent.DeclaredPlace] {
        let placeTypes: Set<String> = ["Place", "LocalBusiness", "Restaurant", "CafeOrCoffeeShop", "BarOrPub", "FoodEstablishment",
                                        "TouristAttraction", "LodgingBusiness", "Hotel", "Museum", "LandmarksOrHistoricalBuildings",
                                        "Bakery", "NightClub", "Store", "ShoppingCenter", "Park", "Beach"]
        var places: [LinkContent.DeclaredPlace] = []
        for m in html.matches(of: /<script[^>]*application\/ld\+json[^>]*>([\s\S]*?)<\/script>/.ignoresCase()) {
            guard let data = String(m.1).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            func visit(_ node: Any) {
                if let array = node as? [Any] { array.forEach(visit); return }
                guard let obj = node as? [String: Any] else { return }
                if let graph = obj["@graph"] { visit(graph) }
                let types = (obj["@type"] as? [String]) ?? [(obj["@type"] as? String) ?? ""]
                if types.contains(where: placeTypes.contains), let name = obj["name"] as? String {
                    var address: String?
                    if let a = obj["address"] as? [String: Any] {
                        address = ["streetAddress", "addressLocality", "addressRegion", "addressCountry"]
                            .compactMap { a[$0] as? String }.joined(separator: ", ")
                    } else { address = obj["address"] as? String }
                    var coordinate: CLLocationCoordinate2D?
                    if let geo = obj["geo"] as? [String: Any],
                       let lat = Double("\(geo["latitude"] ?? "")"), let lon = Double("\(geo["longitude"] ?? "")") {
                        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                    places.append(.init(name: decodeEntities(name), address: address, coordinate: coordinate))
                }
                for key in ["itemListElement", "item", "mainEntity", "about", "location"] { if let v = obj[key] { visit(v) } }
            }
            visit(json)
        }
        return places
    }

    /// The article part of a page for place extraction: menus/header/footer removed, headings first
    /// (list articles put each place in a heading), then body text.
    static func articleText(_ html: String, limit: Int) -> String {
        var s = html.replacing(/<(script|style|noscript|svg|nav|header|footer|aside|form|button)\b[\s\S]*?<\/\1>/.ignoresCase(), with: " ")
        // Prefer <main>; otherwise the largest <article> (many pages use small <article> cards for "related" links).
        if let main = s.firstMatch(of: /<main\b[^>]*>([\s\S]*)<\/main>/.ignoresCase()) {
            s = String(main.1)
        } else if let biggest = s.matches(of: /<article\b[^>]*>([\s\S]*?)<\/article>/.ignoresCase()).max(by: { $0.1.count < $1.1.count }),
                  biggest.1.count > 2_000 {
            s = String(biggest.1)
        }
        let headings = s.matches(of: /<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/.ignoresCase())
            .map { decodeEntities(String($0.1).replacing(/<[^>]+>/, with: " ")).replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && $0.count <= 120 }
        let body = visibleText(s, limit: limit)
        return String((headings.joined(separator: "\n") + "\n" + body).prefix(limit))
    }

    /// Readable text from a page (scripts/styles/tags stripped), capped for the extractor.
    static func visibleText(_ html: String, limit: Int) -> String {
        var s = html.replacing(/<(script|style|noscript|svg)[\s\S]*?<\/\1>/.ignoresCase(), with: " ")
        s = s.replacing(/<br\s*\/?>|<\/(p|div|li|h\d)>/.ignoresCase(), with: "\n")
        s = s.replacing(/<[^>]+>/, with: " ")
        s = decodeEntities(s)
        s = s.replacing(/[ \t]+/, with: " ").replacing(/\n\s*\n+/, with: "\n")
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let regex = try! Regex("\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')").ignoresCase()
        guard let m = tag.firstMatch(of: regex) else { return nil }
        return (m.output[2].substring ?? m.output[3].substring).map(String.init)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#x27;": "'"] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out.replacing(/&#(\d+);/) { m in String(UnicodeScalar(UInt32(m.1) ?? 32).map(Character.init) ?? " ") }
    }
}
