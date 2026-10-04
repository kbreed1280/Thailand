import CoreData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Enums

/// Plotline-style spot categories.
enum SpotCategory: String, CaseIterable, Identifiable {
    case eat, brew, sip, vibe, explore, go

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eat: "Eat"
        case .brew: "Brew"
        case .sip: "Sip"
        case .vibe: "Vibe"
        case .explore: "Explore"
        case .go: "Go"
        }
    }

    /// What it covers, for pickers.
    var subtitle: String {
        switch self {
        case .eat: "Restaurants, street food, markets"
        case .brew: "Coffee, cafés, bakeries"
        case .sip: "Bars, rooftops, nightlife"
        case .vibe: "Shops, spas, neighborhoods"
        case .explore: "Temples, sights, nature, beaches"
        case .go: "Hotels, transport, tours"
        }
    }

    var systemImage: String {
        switch self {
        case .eat: "fork.knife"
        case .brew: "cup.and.saucer.fill"
        case .sip: "wineglass.fill"
        case .vibe: "sparkles"
        case .explore: "binoculars.fill"
        case .go: "airplane"
        }
    }

    var color: Color {
        switch self {
        case .eat: Theme.coral
        case .brew: Color(hex: "#8B5A3C")
        case .sip: Color(hex: "#7B4FC9")
        case .vibe: Color(hex: "#E0559A")
        case .explore: Theme.lagoon
        case .go: Color(hex: "#3B82F6")
        }
    }

    /// Best category for an Apple Maps point of interest.
    init(poi: MKPointOfInterestCategory?) {
        switch poi {
        case .restaurant?, .foodMarket?: self = .eat
        case .cafe?, .bakery?: self = .brew
        case .brewery?, .winery?, .nightlife?, .distillery?: self = .sip
        case .store?, .spa?, .beauty?, .fitnessCenter?, .musicVenue?, .theater?, .movieTheater?: self = .vibe
        case .hotel?, .airport?, .publicTransport?, .carRental?, .gasStation?, .parking?, .evCharger?: self = .go
        case .museum?, .park?, .nationalPark?, .beach?, .landmark?, .castle?, .amusementPark?, .aquarium?, .zoo?,
             .marina?, .hiking?, .fortress?, .nationalMonument?, .stadium?, .university?, .library?, .planetarium?:
            self = .explore
        default: self = .explore
        }
    }

    /// From a free-text category word (LLM output or caption).
    init(word: String) {
        let w = word.lowercased()
        if ["eat", "food", "restaurant", "street food", "market", "noodle", "dinner", "lunch", "breakfast"].contains(where: w.contains) { self = .eat }
        else if ["brew", "coffee", "cafe", "café", "bakery", "dessert", "tea"].contains(where: w.contains) { self = .brew }
        else if ["sip", "bar", "rooftop", "cocktail", "club", "nightlife", "beer", "wine"].contains(where: w.contains) { self = .sip }
        else if ["go", "hotel", "hostel", "resort", "airport", "transport", "tour", "ferry"].contains(where: w.contains) { self = .go }
        else if ["vibe", "shop", "spa", "massage", "mall", "neighborhood", "boutique"].contains(where: w.contains) { self = .vibe }
        else { self = .explore }
    }
}

enum SpotStatus: String { case draft, confirmed }

enum SourcePlatform: String, CaseIterable {
    case tiktok, instagram, youtube, googleMaps, screenshot, web

    var title: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .googleMaps: "Google Maps"
        case .screenshot: "Screenshot"
        case .web: "Web"
        }
    }

    var systemImage: String {
        switch self {
        case .tiktok: "music.note"
        case .instagram: "camera.fill"
        case .youtube: "play.rectangle.fill"
        case .googleMaps: "map.fill"
        case .screenshot: "photo"
        case .web: "safari"
        }
    }

    var isVideo: Bool { [.tiktok, .instagram, .youtube].contains(self) }

    init(url: URL?) {
        guard let host = url?.host?.lowercased() else { self = .screenshot; return }
        if host.hasSuffix("tiktok.com") { self = .tiktok }
        else if host.hasSuffix("instagram.com") { self = .instagram }
        else if host.hasSuffix("youtube.com") || host == "youtu.be" { self = .youtube }
        else if host.contains("maps.app.goo.gl") || (host.hasSuffix("google.com") && (url?.path.hasPrefix("/maps") ?? false))
                    || host == "goo.gl" || host.hasPrefix("maps.google.") { self = .googleMaps }
        else { self = .web }
    }
}

/// Where an import is in the pipeline.
enum ImportStatus: String {
    case queued, fetching, extracting, locating, ready, failed

    var title: String {
        switch self {
        case .queued: "Waiting…"
        case .fetching: "Reading the post…"
        case .extracting: "Finding places…"
        case .locating: "Pinning on the map…"
        case .ready: "Ready to review"
        case .failed: "Couldn't import"
        }
    }

    var isWorking: Bool { [.queued, .fetching, .extracting, .locating].contains(self) }

    /// 0–1 for progress bars.
    var progress: Double {
        switch self {
        case .queued: 0.05
        case .fetching: 0.25
        case .extracting: 0.55
        case .locating: 0.8
        case .ready, .failed: 1
        }
    }
}

// MARK: - Managed objects

@objc(Spot)
final class Spot: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var address: String?
    @NSManaged var city: String?
    @NSManaged var hasCoordinate: Bool
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var categoryRaw: String?
    @NSManaged var appleMapsID: String?
    @NSManaged var phone: String?
    @NSManaged var website: String?
    @NSManaged var statusRaw: String?
    @NSManaged var isFavorite: Bool
    @NSManaged var isVisited: Bool
    @NSManaged var notes: String?
    @NSManaged var reportReason: String?
    @NSManaged var addedBy: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var trip: Trip?
    @NSManaged var scoops: NSSet?

    var displayName: String { (name ?? "").isEmpty ? "Unnamed spot" : name! }

    var category: SpotCategory {
        get { SpotCategory(rawValue: categoryRaw ?? "") ?? .explore }
        set { categoryRaw = newValue.rawValue }
    }

    var status: SpotStatus {
        get { SpotStatus(rawValue: statusRaw ?? "") ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var isDraft: Bool { status == .draft }

    var coordinate: CLLocationCoordinate2D? {
        get { hasCoordinate ? CLLocationCoordinate2D(latitude: latitude, longitude: longitude) : nil }
        set {
            hasCoordinate = newValue != nil
            latitude = newValue?.latitude ?? 0
            longitude = newValue?.longitude ?? 0
        }
    }

    /// Drafts that couldn't be matched to a real place.
    var isUnplotted: Bool { !hasCoordinate }

    var sortedScoops: [SpotScoop] {
        (scoops as? Set<SpotScoop> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var sources: [SpotSource] { sortedScoops.compactMap(\.source) }

    func touch() { updatedAt = .now }

    /// Fills place details from an Apple Maps result.
    func apply(_ item: MKMapItem) {
        name = item.name ?? name
        address = item.placemark.title ?? ""
        city = item.placemark.locality ?? item.placemark.administrativeArea ?? city
        coordinate = item.placemark.coordinate
        appleMapsID = item.identifier?.rawValue ?? ""
        phone = item.phoneNumber ?? ""
        website = item.url?.absoluteString ?? ""
        if let poi = item.pointOfInterestCategory { category = SpotCategory(poi: poi) }
        touch()
    }
}

@objc(SpotSource)
final class SpotSource: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var urlString: String?
    @NSManaged var platformRaw: String?
    @NSManaged var creator: String?
    @NSManaged var title: String?
    @NSManaged var extractedText: String?
    @NSManaged var thumbnailURL: String?
    @NSManaged var statusRaw: String?
    @NSManaged var errorMessage: String?
    @NSManaged var folder: String?
    @NSManaged var extractor: String?
    @NSManaged var addedBy: String?
    @NSManaged var createdAt: Date?
    @NSManaged var trip: Trip?
    @NSManaged var scoops: NSSet?

    var url: URL? { (urlString ?? "").isEmpty ? nil : URL(string: urlString!) }
    var platform: SourcePlatform { SourcePlatform(rawValue: platformRaw ?? "") ?? .web }

    var status: ImportStatus {
        get { ImportStatus(rawValue: statusRaw ?? "") ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var sortedScoops: [SpotScoop] {
        (scoops as? Set<SpotScoop> ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    var spots: [Spot] { sortedScoops.compactMap(\.spot) }
    var draftSpots: [Spot] { spots.filter(\.isDraft) }

    var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(120)) }
        return platform == .screenshot ? "Screenshot" : (url?.host ?? "Link")
    }
}

@objc(SpotScoop)
final class SpotScoop: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var recommendation: String?
    @NSManaged var whatToOrder: String?
    @NSManaged var whyItMatters: String?
    @NSManaged var mentionedAs: String?
    @NSManaged var createdAt: Date?
    @NSManaged var spot: Spot?
    @NSManaged var source: SpotSource?

    var hasContent: Bool {
        ![recommendation, whatToOrder, whyItMatters].allSatisfy { ($0 ?? "").isEmpty }
    }
}

extension Trip {
    var allSpots: [Spot] { (value(forKey: "spots") as? Set<Spot> ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) } }
    var confirmedSpots: [Spot] { allSpots.filter { !$0.isDraft } }
    var draftSpots: [Spot] { allSpots.filter(\.isDraft) }
    var allSpotSources: [SpotSource] {
        (value(forKey: "spotSources") as? Set<SpotSource> ?? []).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}
