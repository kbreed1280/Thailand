import CoreData
import CoreLocation
import MapKit

/// Save-from-anywhere: shared link/screenshot → read post → extract places → pin on Apple Maps →
/// draft spots (grouped by source) for you to confirm. Runs on the iPhone; nothing is re-hosted.
@MainActor
final class ImportPipeline: ObservableObject {
    static let shared = ImportPipeline()

    @Published private(set) var working: Set<NSManagedObjectID> = []

    var locator: PlaceLocating = AppleMapsLocator()
    var reader: (URL, String?) async -> LinkContent = { await LinkReader.read($0, extraText: $1) }
    var extractor: () -> PlaceExtracting = { PlaceExtractor.current }

    /// Turns links waiting in the Share-extension inbox into sources on this trip, then imports them.
    func processInbox(into trip: Trip, context: NSManagedObjectContext) async {
        migrateLegacyVideos(in: trip, context: context)
        for link in SharedInbox.load() {
            addSource(url: link.url, text: link.text, to: trip, context: context)
            SharedInbox.remove(link.id)
        }
        save(context)
        await importPending(in: trip, context: context)
    }

    /// Adds a link or screenshot text as a queued source (skips links already imported to this trip).
    @discardableResult
    func addSource(url: URL?, text: String?, to trip: Trip, context: NSManagedObjectContext) -> SpotSource? {
        if let url, trip.allSpotSources.contains(where: { $0.urlString == url.absoluteString }) { return nil }
        let source = SpotSource(context: context)
        source.placeInSameStore(as: trip)
        source.uuid = UUID()
        source.urlString = url?.absoluteString ?? ""
        source.platformRaw = (url == nil ? SourcePlatform.screenshot : SourcePlatform(url: url)).rawValue
        // Shared text is "caption + link" from TikTok, or recognized screenshot text.
        source.extractedText = text ?? ""
        source.status = .queued
        source.addedBy = AppSettings.displayName
        source.createdAt = .now
        source.trip = trip
        return source
    }

    func importPending(in trip: Trip, context: NSManagedObjectContext) async {
        for source in trip.allSpotSources where source.status == .queued || (source.status.isWorking && !working.contains(source.objectID)) {
            await run(source, in: trip, context: context)
        }
    }

    /// Re-runs one source from scratch (keeps confirmed spots, replaces its drafts).
    func retry(_ source: SpotSource, context: NSManagedObjectContext) async {
        guard let trip = source.trip else { return }
        for scoop in source.sortedScoops where scoop.spot?.isDraft == true {
            if let spot = scoop.spot, spot.sortedScoops.count <= 1 { context.delete(spot) }
            context.delete(scoop)
        }
        source.status = .queued
        save(context)
        await run(source, in: trip, context: context)
    }

    // MARK: Pipeline

    private func run(_ source: SpotSource, in trip: Trip, context: NSManagedObjectContext) async {
        guard Subscription.shared.consumeImport() else {
            source.errorMessage = Subscription.limitMessage
            set(source, .failed, context)
            return
        }
        working.insert(source.objectID)
        defer { working.remove(source.objectID) }

        // 1. Read the post (caption, description, page facts).
        set(source, .fetching, context)
        let sharedText = source.extractedText ?? ""
        let content: LinkContent
        if let url = source.url {
            content = await reader(url, sharedText.isEmpty ? nil : sharedText)
        } else {
            content = LinkContent(url: nil, platform: .screenshot, title: "Screenshot", text: sharedText)
        }
        if !content.title.isEmpty { source.title = content.title }
        source.creator = content.creator
        source.thumbnailURL = content.thumbnailURL?.absoluteString ?? ""
        source.extractedText = String(content.text.prefix(8_000))
        if let canonical = content.url, source.url != nil { source.urlString = canonical.absoluteString }
        source.platformRaw = content.platform.rawValue

        guard !content.text.isEmpty || !content.declaredPlaces.isEmpty else {
            source.errorMessage = "Couldn't read this post. It may be private or the site blocks previews. Add the place yourself or share a screenshot."
            set(source, .failed, context)
            return
        }

        // 2. Extract every place mentioned.
        set(source, .extracting, context)
        let (places, used) = await PlaceExtractor.extract(from: content, using: extractor())
        source.extractor = used
        let area = TravelArea.detect(in: content.text)

        // 3. Pin each on Apple Maps and save as a draft (or attach to a spot you already have).
        set(source, .locating, context)
        var added = 0
        for place in places {
            let declared = content.declaredPlaces.first { $0.name == place.name }?.coordinate
            let match = await locator.locate(place, near: area, declared: declared)
            if place.isGuess && match == nil { continue } // don't create junk "unplotted" spots from guesses
            attach(place, match: match, declared: declared, from: source, in: trip, context: context)
            added += 1
        }
        source.errorMessage = added == 0 ? "No specific places found. File it in a folder or add the place yourself." : ""
        set(source, .ready, context)
    }

    private func attach(_ place: ExtractedPlace, match: MKMapItem?, declared: CLLocationCoordinate2D?,
                        from source: SpotSource, in trip: Trip, context: NSManagedObjectContext) {
        let coordinate = match?.placemark.coordinate ?? declared
        let spot: Spot
        if let existing = Self.existingSpot(name: match?.name ?? place.name, coordinate: coordinate,
                                            appleMapsID: match?.identifier?.rawValue, in: trip.allSpots) {
            spot = existing // same place from another post: one spot, several scoops
        } else {
            spot = Spot(context: context)
            spot.placeInSameStore(as: trip)
            spot.uuid = UUID()
            spot.name = place.name
            spot.category = place.category
            spot.city = place.cityHint
            spot.status = .draft
            spot.addedBy = AppSettings.displayName
            spot.createdAt = .now
            spot.trip = trip
            if let match { spot.apply(match); if match.pointOfInterestCategory == nil { spot.category = place.category } }
            else if let declared { spot.coordinate = declared }
        }
        let scoop = SpotScoop(context: context)
        scoop.placeInSameStore(as: trip)
        scoop.uuid = UUID()
        scoop.recommendation = place.recommendation
        scoop.whatToOrder = place.whatToOrder
        scoop.whyItMatters = place.whyItMatters
        scoop.mentionedAs = place.name
        scoop.createdAt = .now
        scoop.spot = spot
        scoop.source = source
        spot.touch()
    }

    /// Same place if Apple Maps IDs match, or names match closely within ~75 m.
    nonisolated static func existingSpot(name: String, coordinate: CLLocationCoordinate2D?, appleMapsID: String?, in spots: [Spot]) -> Spot? {
        if let id = appleMapsID, !id.isEmpty, let hit = spots.first(where: { $0.appleMapsID == id }) { return hit }
        guard let coordinate else {
            return spots.first { !$0.hasCoordinate && NameMatch.similarity($0.displayName, name) >= 0.9 }
        }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return spots.first { spot in
            guard let c = spot.coordinate else { return false }
            return here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 75
                && NameMatch.similarity(spot.displayName, name) >= 0.6
        }
    }

    private func set(_ source: SpotSource, _ status: ImportStatus, _ context: NSManagedObjectContext) {
        source.status = status
        save(context)
    }

    private func save(_ context: NSManagedObjectContext) {
        ItineraryStore(context: context).save()
    }

    // MARK: One-time move of step-12 TikTok saves (wish-list items) into spots

    func migrateLegacyVideos(in trip: Trip, context: NSManagedObjectContext) {
        let key = "spotsMigrated-\(trip.uuid?.uuidString ?? "")"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for item in trip.sortedWishItems where TravelVideos.isVideoLink(item.link) {
            let lines = (item.notes ?? "").split(separator: "\n").map(String.init)
            guard let source = addSource(url: URL(string: item.link ?? ""), text: nil, to: trip, context: context) else { continue }
            source.creator = lines.first?.components(separatedBy: " · ").dropFirst().first ?? ""
            source.title = lines.dropFirst().first { !$0.hasPrefix("Area: ") && !$0.hasPrefix("Folder: ") } ?? item.title ?? ""
            source.folder = item.videoFolder ?? ""
            source.extractor = "saved-before-update"
            source.status = .ready
            if let c = item.coordinate {
                let spot = Spot(context: context)
                spot.placeInSameStore(as: trip)
                spot.uuid = UUID()
                spot.name = item.title
                spot.address = item.address
                spot.coordinate = c
                spot.city = TravelVideos.area(of: item)
                spot.category = item.category == .meal ? .eat : item.category == .hotel ? .go : .explore
                spot.status = .confirmed
                spot.createdAt = item.createdAt ?? .now
                spot.trip = trip
                let scoop = SpotScoop(context: context)
                scoop.placeInSameStore(as: trip)
                scoop.uuid = UUID()
                scoop.createdAt = .now
                scoop.spot = spot
                scoop.source = source
            }
            context.delete(item)
        }
        save(context)
        UserDefaults.standard.set(true, forKey: key)
    }
}
