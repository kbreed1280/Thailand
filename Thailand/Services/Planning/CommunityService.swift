import CloudKit
import CoreData
import CoreLocation
import CryptoKit
import Foundation

/// Opt-in community layer on the CloudKit public database. When you turn it on, spots you
/// confirm are shared as anonymous tips (place + the inside scoop + a link to the original
/// post, never your notes, photos or trip). Others see "trending nearby" places that several
/// people saved, and a tip only when several independent sources agree on it.
///
/// CloudKit setup (Console → Schema): record type `CommunityTip`; add Queryable indexes on
/// `cell`, `installID` and `recordName`, then Deploy Schema Changes to Production before a TestFlight build.
struct CommunityTip: Equatable {
    var placeKey: String
    var name: String
    var latitude: Double
    var longitude: Double
    var category: String
    var city: String
    var recommendation: String
    var whatToOrder: String
    var sourceURL: String
    var creator: String
    /// "@username" when the contributor chose to show it, else empty (anonymous).
    var contributor: String
    /// Random per-install id: one person saving a place twice counts once.
    var installID: String

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct CommunityPlace: Identifiable, Equatable {
    let placeKey: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let category: SpotCategory
    let city: String
    /// Independent sources (distinct posts, or people when there's no post).
    let sourceCount: Int
    /// Dishes / tips mentioned by at least two independent sources.
    let agreedOrders: [String]
    let agreedTip: String?
    /// Creators and contributors to credit.
    let credits: [String]
    let sourceURLs: [String]
    var id: String { placeKey }

    static func == (a: CommunityPlace, b: CommunityPlace) -> Bool { a.placeKey == b.placeKey && a.sourceCount == b.sourceCount }
}

enum CommunityAggregator {
    /// Minimum independent sources before a place trends or a tip is shown.
    static let agreement = 2

    static func placeKey(name: String, appleMapsID: String?, coordinate: CLLocationCoordinate2D) -> String {
        if let id = appleMapsID, !id.isEmpty { return "apple:\(id)" }
        let tokens = NameMatch.tokens(name).sorted().joined(separator: "-")
        return String(format: "geo:%@@%.3f,%.3f", tokens, coordinate.latitude, coordinate.longitude)
    }

    /// ~5 km grid cell, for "nearby" queries.
    static func cell(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%d:%d", Int((c.latitude / 0.05).rounded(.down)), Int((c.longitude / 0.05).rounded(.down)))
    }

    static func cells(around c: CLLocationCoordinate2D) -> [String] {
        let lat = Int((c.latitude / 0.05).rounded(.down)), lon = Int((c.longitude / 0.05).rounded(.down))
        return (-1...1).flatMap { dy in (-1...1).map { dx in "\(lat + dy):\(lon + dx)" } }
    }

    private static func sourceID(_ t: CommunityTip) -> String { t.sourceURL.isEmpty ? "install:\(t.installID)" : t.sourceURL }

    /// Splits "pad kra pao, crab omelette & mango sticky rice" into normalized dishes.
    static func dishes(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: "&", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { $0.count > 2 }
    }

    static func aggregate(_ tips: [CommunityTip]) -> [CommunityPlace] {
        Dictionary(grouping: tips, by: \.placeKey).compactMap { key, group -> CommunityPlace? in
            guard let first = group.first else { return nil }
            let bySource = Dictionary(grouping: group, by: sourceID)
            // Each source votes once per dish.
            var votes: [String: Set<String>] = [:]
            for (source, tips) in bySource {
                for dish in Set(tips.flatMap { dishes($0.whatToOrder) }) { votes[dish, default: []].insert(source) }
            }
            let agreed = votes.filter { $0.value.count >= agreement }
                .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
                .map(\.key)
            // A recommendation is shown only if it echoes an agreed dish, so one loud post can't set the tip.
            let tip = agreed.isEmpty ? nil : group.map(\.recommendation)
                .first { rec in !rec.isEmpty && agreed.contains { rec.lowercased().contains($0) } }
            let credits = Array(Set(group.map(\.creator).filter { !$0.isEmpty } + group.map(\.contributor).filter { !$0.isEmpty })).sorted()
            return CommunityPlace(placeKey: key, name: first.name, coordinate: first.coordinate,
                                  category: SpotCategory(rawValue: first.category) ?? .explore, city: first.city,
                                  sourceCount: bySource.count, agreedOrders: agreed, agreedTip: tip, credits: credits,
                                  sourceURLs: Array(Set(group.map(\.sourceURL).filter { !$0.isEmpty })).sorted())
        }
    }

    static func trending(_ tips: [CommunityTip], near center: CLLocationCoordinate2D, radius: CLLocationDistance = 5_000) -> [CommunityPlace] {
        aggregate(tips)
            .filter { $0.sourceCount >= agreement && AutoPlanner.distance($0.coordinate, center) <= radius }
            .sorted { $0.sourceCount != $1.sourceCount ? $0.sourceCount > $1.sourceCount : $0.name < $1.name }
    }
}

@MainActor
final class CommunityService: ObservableObject {
    static let shared = CommunityService()

    static let enabledKey = "communityEnabled"
    static let showUsernameKey = "communityShowUsername"
    private static let installIDKey = "communityInstallID"
    static let recordType = "CommunityTip"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var installID: String {
        if let id = UserDefaults.standard.string(forKey: installIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: installIDKey)
        return id
    }

    @Published private(set) var lastError: String?
    private var pending: Set<NSManagedObjectID> = []
    private var observer: NSObjectProtocol?

    /// Shares spots as they're confirmed or edited (only while opted in).
    func startObserving(_ context: NSManagedObjectContext) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: context, queue: .main) { [weak self] note in
            let changed = ((note.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
                .union((note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? [])
            let ids = changed.compactMap { ($0 as? Spot)?.objectID }
            MainActor.assumeIsolated {
                guard let self, Self.isEnabled, !ids.isEmpty else { return }
                let wasEmpty = self.pending.isEmpty
                self.pending.formUnion(ids)
                guard wasEmpty else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    let batch = self.pending
                    self.pending = []
                    for id in batch {
                        if let spot = try? context.existingObject(with: id) as? Spot, !spot.isDeleted { await self.share(spot) }
                    }
                }
            }
        }
    }

    /// Shares every confirmed spot you have (when you first opt in).
    func shareAll(in context: NSManagedObjectContext) async {
        let spots = (try? context.fetch(NSFetchRequest<Spot>(entityName: "Spot"))) ?? []
        for spot in spots where spot.status == .confirmed { await share(spot) }
    }

    private var database: CKDatabase { CKContainer(identifier: PersistenceController.containerIdentifier).publicCloudDatabase }

    static func tips(for spot: Spot) -> [CommunityTip] {
        guard let c = spot.coordinate, spot.status == .confirmed else { return [] }
        let key = CommunityAggregator.placeKey(name: spot.displayName, appleMapsID: spot.appleMapsID, coordinate: c)
        let showName = UserDefaults.standard.bool(forKey: showUsernameKey)
        let username = UserDefaults.standard.string(forKey: AppSettings.usernameKey) ?? ""
        let contributor = showName && !username.isEmpty ? "@\(username)" : ""
        func tip(_ scoop: SpotScoop?) -> CommunityTip {
            CommunityTip(placeKey: key, name: spot.displayName, latitude: c.latitude, longitude: c.longitude,
                         category: spot.category.rawValue, city: spot.city ?? "",
                         recommendation: scoop?.recommendation ?? "", whatToOrder: scoop?.whatToOrder ?? "",
                         sourceURL: scoop?.source?.urlString ?? "", creator: scoop?.source?.creator ?? "",
                         contributor: contributor, installID: installID)
        }
        let scoops = spot.sortedScoops
        return scoops.isEmpty ? [tip(nil)] : scoops.map(tip)
    }

    /// Shares a confirmed spot (only when you've opted in). Same place + post from the same
    /// install overwrites the earlier record, so re-saving never double counts.
    func share(_ spot: Spot) async {
        guard Self.isEnabled else { return }
        let records = Self.tips(for: spot).map(record)
        guard !records.isEmpty else { return }
        do {
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Removes everything this install shared (when you opt out).
    func withdrawAll() async {
        let predicate = NSPredicate(format: "installID == %@", Self.installID)
        guard let (results, _) = try? await database.records(matching: CKQuery(recordType: Self.recordType, predicate: predicate)) else { return }
        let ids = results.map(\.0)
        _ = try? await database.modifyRecords(saving: [], deleting: ids)
    }

    func trending(near center: CLLocationCoordinate2D) async -> [CommunityPlace] {
        CommunityAggregator.trending(await fetch(near: center), near: center)
    }

    /// What the community agrees on for one place, if enough sources agree.
    func consensus(for spot: Spot) async -> CommunityPlace? {
        guard let c = spot.coordinate else { return nil }
        let key = CommunityAggregator.placeKey(name: spot.displayName, appleMapsID: spot.appleMapsID, coordinate: c)
        let place = CommunityAggregator.aggregate(await fetch(near: c).filter { $0.placeKey == key }).first
        return place.flatMap { $0.sourceCount >= CommunityAggregator.agreement ? $0 : nil }
    }

    private func fetch(near center: CLLocationCoordinate2D) async -> [CommunityTip] {
        let predicate = NSPredicate(format: "cell IN %@", CommunityAggregator.cells(around: center))
        do {
            let (results, _) = try await database.records(matching: CKQuery(recordType: Self.recordType, predicate: predicate), resultsLimit: 400)
            lastError = nil
            return results.compactMap { try? $0.1.get() }.compactMap(Self.tip)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    private func record(_ t: CommunityTip) -> CKRecord {
        let digest = SHA256.hash(data: Data("\(t.placeKey)|\(t.sourceURL)|\(t.installID)".utf8))
        let name = "tip-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let r = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: name))
        r["placeKey"] = t.placeKey
        r["name"] = t.name
        r["location"] = CLLocation(latitude: t.latitude, longitude: t.longitude)
        r["cell"] = CommunityAggregator.cell(t.coordinate)
        r["category"] = t.category
        r["city"] = t.city
        r["recommendation"] = String(t.recommendation.prefix(400))
        r["whatToOrder"] = String(t.whatToOrder.prefix(200))
        r["sourceURL"] = t.sourceURL
        r["creator"] = t.creator
        r["contributor"] = t.contributor
        r["installID"] = t.installID
        return r
    }

    private static func tip(_ r: CKRecord) -> CommunityTip? {
        guard let key = r["placeKey"] as? String, let name = r["name"] as? String, let loc = r["location"] as? CLLocation else { return nil }
        return CommunityTip(placeKey: key, name: name, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                            category: r["category"] as? String ?? "", city: r["city"] as? String ?? "",
                            recommendation: r["recommendation"] as? String ?? "", whatToOrder: r["whatToOrder"] as? String ?? "",
                            sourceURL: r["sourceURL"] as? String ?? "", creator: r["creator"] as? String ?? "",
                            contributor: r["contributor"] as? String ?? "", installID: r["installID"] as? String ?? "")
    }
}
