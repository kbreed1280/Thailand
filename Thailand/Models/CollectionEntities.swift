import CoreData
import CoreTransferable
import CoreLocation
import UniformTypeIdentifiers

enum CollectionKind: String, CaseIterable, Identifiable {
    case trip, city, theme
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trip: "Trip"
        case .city: "City"
        case .theme: "Theme"
        }
    }
}

@objc(SpotCollection)
final class SpotCollection: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var emoji: String?
    @NSManaged var kindRaw: String?
    @NSManaged var notes: String?
    @NSManaged var sortIndex: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var trip: Trip?
    @NSManaged var entries: NSSet?

    var displayName: String { (name ?? "").isEmpty ? "Untitled" : name! }
    var kind: CollectionKind {
        get { CollectionKind(rawValue: kindRaw ?? "") ?? .theme }
        set { kindRaw = newValue.rawValue }
    }

    var sortedEntries: [CollectionEntry] {
        (entries as? Set<CollectionEntry> ?? []).filter { $0.spot != nil }.sorted { $0.sortIndex < $1.sortIndex }
    }

    var spots: [Spot] { sortedEntries.compactMap(\.spot) }

    func contains(_ spot: Spot) -> Bool { sortedEntries.contains { $0.spot == spot } }
}

@objc(CollectionEntry)
final class CollectionEntry: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var note: String?
    @NSManaged var sortIndex: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var collection: SpotCollection?
    @NSManaged var spot: Spot?
}

extension Trip {
    @NSManaged var destination: String?
    @NSManaged var vibe: String?

    var sortedCollections: [SpotCollection] {
        (value(forKey: "collections") as? Set<SpotCollection> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}

extension Spot {
    var collections: [SpotCollection] {
        (value(forKey: "collectionEntries") as? Set<CollectionEntry> ?? []).compactMap(\.collection)
    }
}

// MARK: - Collection store

enum CollectionStore {
    @discardableResult
    static func create(name: String, emoji: String, kind: CollectionKind, in trip: Trip, context: NSManagedObjectContext) -> SpotCollection {
        let c = SpotCollection(context: context)
        c.placeInSameStore(as: trip)
        c.uuid = UUID()
        c.name = name
        c.emoji = emoji
        c.kind = kind
        c.sortIndex = Int64((trip.sortedCollections.map(\.sortIndex).max() ?? -1) + 1)
        c.createdAt = .now
        c.updatedAt = .now
        c.trip = trip
        return c
    }

    static func add(_ spot: Spot, to collection: SpotCollection, note: String = "", context: NSManagedObjectContext) {
        guard !collection.contains(spot) else { return }
        let e = CollectionEntry(context: context)
        e.placeInSameStore(as: collection)
        e.uuid = UUID()
        e.note = note
        e.sortIndex = Int64((collection.sortedEntries.map(\.sortIndex).max() ?? -1) + 1)
        e.createdAt = .now
        e.collection = collection
        e.spot = spot
        collection.updatedAt = .now
    }

    static func remove(_ spot: Spot, from collection: SpotCollection, context: NSManagedObjectContext) {
        for e in collection.sortedEntries where e.spot == spot {
            e.collection = nil
            e.spot = nil
            context.delete(e)
        }
        collection.updatedAt = .now
    }

    static func move(in collection: SpotCollection, from source: IndexSet, to destination: Int) {
        var entries = collection.sortedEntries
        entries.move(fromOffsets: source, toOffset: destination)
        for (i, e) in entries.enumerated() { e.sortIndex = Int64(i) }
        collection.updatedAt = .now
    }
}

// MARK: - Sharing a collection as a .wanderhub file (Messages, AirDrop, Mail…)

extension UTType {
    /// Declared in Info.plist (UTExportedTypeDeclarations) so WanderHub opens these files.
    static let wanderhubCollection = UTType(exportedAs: "com.kbreed.wanderhub.collection", conformingTo: .json)
}

/// Portable copy of a collection: places, your notes and the inside scoop with links back to
/// the original posts. No videos or photos are included, only links and facts.
struct SharedCollection: Codable, Equatable, Transferable {
    struct SharedSpot: Codable, Equatable, Identifiable {
        var id = UUID()
        var name: String
        var address: String
        var city: String
        var latitude: Double?
        var longitude: Double?
        var category: String
        var appleMapsID: String
        var note: String
        var tips: [Tip]

        var coordinate: CLLocationCoordinate2D? {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    struct Tip: Codable, Equatable {
        var recommendation: String
        var whatToOrder: String
        var whyItMatters: String
        var sourceURL: String
        var creator: String
    }

    var format = 1
    var name: String
    var emoji: String
    var notes: String
    var sharedBy: String
    var sharedAt = Date()
    var spots: [SharedSpot]

    init(name: String, emoji: String, notes: String, sharedBy: String, spots: [SharedSpot]) {
        self.name = name
        self.emoji = emoji
        self.notes = notes
        self.sharedBy = sharedBy
        self.spots = spots
    }

    init(_ collection: SpotCollection, sharedBy: String) {
        self.init(name: collection.displayName, emoji: collection.emoji ?? "📍", notes: collection.notes ?? "",
                  sharedBy: sharedBy, spots: collection.sortedEntries.compactMap { entry in
            guard let spot = entry.spot else { return nil }
            return SharedSpot(spot, note: entry.note ?? "")
        })
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .wanderhubCollection)
            .suggestedFileName { "\($0.name).wanderhub" }
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    static func decode(_ data: Data) throws -> SharedCollection {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(SharedCollection.self, from: data)
    }
}

extension SharedCollection.SharedSpot {
    init(_ spot: Spot, note: String) {
        self.init(name: spot.displayName, address: spot.address ?? "", city: spot.city ?? "",
                  latitude: spot.coordinate?.latitude, longitude: spot.coordinate?.longitude,
                  category: spot.category.rawValue, appleMapsID: spot.appleMapsID ?? "", note: note,
                  tips: spot.sortedScoops.compactMap { scoop in
                      guard scoop.hasContent || scoop.source?.url != nil else { return nil }
                      return SharedCollection.Tip(recommendation: scoop.recommendation ?? "", whatToOrder: scoop.whatToOrder ?? "",
                                                  whyItMatters: scoop.whyItMatters ?? "", sourceURL: scoop.source?.urlString ?? "",
                                                  creator: scoop.source?.creator ?? "")
                  })
    }
}

/// Saves spots from a shared collection into a trip (all, or one at a time), merging duplicates.
enum CollectionImporter {
    @discardableResult
    static func save(_ shared: SharedCollection.SharedSpot, into collection: SpotCollection?, trip: Trip,
                     context: NSManagedObjectContext) -> Spot {
        let spot = ImportPipeline.existingSpot(name: shared.name, coordinate: shared.coordinate,
                                               appleMapsID: shared.appleMapsID, in: trip.allSpots)
            ?? {
                let s = Spot(context: context)
                s.placeInSameStore(as: trip)
                s.uuid = UUID()
                s.name = shared.name
                s.address = shared.address
                s.city = shared.city
                s.coordinate = shared.coordinate
                s.categoryRaw = shared.category
                s.appleMapsID = shared.appleMapsID
                s.status = .confirmed
                s.addedBy = AppSettings.displayName
                s.createdAt = .now
                s.trip = trip
                return s
            }()
        for tip in shared.tips where !spot.sortedScoops.contains(where: { $0.source?.urlString == tip.sourceURL && !tip.sourceURL.isEmpty }) {
            var source: SpotSource?
            if let url = URL(string: tip.sourceURL), !tip.sourceURL.isEmpty {
                source = trip.allSpotSources.first { $0.urlString == tip.sourceURL }
                    ?? {
                        let s = SpotSource(context: context)
                        s.placeInSameStore(as: trip)
                        s.uuid = UUID()
                        s.urlString = url.absoluteString
                        s.platformRaw = SourcePlatform(url: url).rawValue
                        s.creator = tip.creator
                        s.status = .ready
                        s.extractor = "shared-collection"
                        s.createdAt = .now
                        s.trip = trip
                        return s
                    }()
            }
            let scoop = SpotScoop(context: context)
            scoop.placeInSameStore(as: trip)
            scoop.uuid = UUID()
            scoop.recommendation = tip.recommendation
            scoop.whatToOrder = tip.whatToOrder
            scoop.whyItMatters = tip.whyItMatters
            scoop.createdAt = .now
            scoop.spot = spot
            scoop.source = source
        }
        if !shared.note.isEmpty, (spot.notes ?? "").isEmpty { spot.notes = shared.note }
        if let collection { CollectionStore.add(spot, to: collection, note: shared.note, context: context) }
        return spot
    }

    @discardableResult
    static func saveAll(_ shared: SharedCollection, trip: Trip, context: NSManagedObjectContext) -> SpotCollection {
        let collection = trip.sortedCollections.first { $0.name == shared.name }
            ?? CollectionStore.create(name: shared.name, emoji: shared.emoji, kind: .theme, in: trip, context: context)
        if collection.notes?.isEmpty ?? true { collection.notes = shared.notes }
        for spot in shared.spots { save(spot, into: collection, trip: trip, context: context) }
        return collection
    }
}
