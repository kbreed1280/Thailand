import CoreData
import CloudKit

/// Owns the Core Data stack and iCloud sync/sharing.
///
/// Two stores, as in Apple's "Sharing Core Data objects between iCloud users" design:
///  - **private.sqlite** mirrors your own iCloud private database (trips you created),
///  - **shared.sqlite** mirrors the shared database (trips other people shared with you).
/// `NSPersistentCloudKitContainer` syncs both in the background, merges offline edits, and
/// creates/accepts `CKShare`s for a trip and everything under it.
final class PersistenceController {
    static let containerIdentifier = "iCloud.com.kbreed.thailandtrip"

    static let shared = PersistenceController()

    /// In-memory store with the demo trip, for SwiftUI previews.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        SampleTrip.create(in: controller.viewContext)
        return controller
    }()

    let container: NSPersistentCloudKitContainer
    let isCloudEnabled: Bool
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var viewContext: NSManagedObjectContext { container.viewContext }
    var cloudKitContainer: CKContainer { CKContainer(identifier: Self.containerIdentifier) }

    /// Unit tests run inside the app; keep them away from iCloud.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Thailand", managedObjectModel: TripModel.model)
        isCloudEnabled = !inMemory && !Self.isRunningTests

        if inMemory || !isCloudEnabled {
            let description = NSPersistentStoreDescription()
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            } else {
                description.url = NSPersistentContainer.defaultDirectoryURL().appending(path: "tests.sqlite")
            }
            Self.enableHistory(on: description)
            description.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [description]
        } else {
            let base = NSPersistentContainer.defaultDirectoryURL()

            let privateDescription = NSPersistentStoreDescription(url: base.appending(path: "private.sqlite"))
            Self.enableHistory(on: privateDescription)
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerIdentifier)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            let sharedDescription = NSPersistentStoreDescription(url: base.appending(path: "shared.sqlite"))
            Self.enableHistory(on: sharedDescription)
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerIdentifier)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions

            container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        }

        container.loadPersistentStores { description, error in
            if let error {
                fatalError("Couldn't load the trip database: \(error)")
            }
        }

        for store in container.persistentStoreCoordinator.persistentStores {
            if store.url?.lastPathComponent == "shared.sqlite" {
                sharedStore = store
            } else {
                privateStore = store
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
        container.viewContext.name = "viewContext"
        try? container.viewContext.setQueryGenerationFrom(.current)
    }

    private static func enableHistory(on description: NSPersistentStoreDescription) {
        // History tracking + remote change notifications are what CloudKit sync relies on.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            print("Save failed: \(error)")
        }
    }

    // MARK: Sharing helpers

    /// The CKShare for a trip, if it has been shared (by you or with you).
    func share(for trip: Trip) -> CKShare? {
        guard isCloudEnabled, !trip.objectID.isTemporaryID else { return nil }
        return (try? container.fetchShares(matching: [trip.objectID]))?[trip.objectID]
    }

    /// True for trips someone else shared with you.
    func isSharedWithMe(_ trip: Trip) -> Bool {
        guard let sharedStore else { return false }
        return trip.objectID.persistentStore == sharedStore
    }

    /// False when the owner gave you read-only access.
    func canEdit(_ trip: Trip) -> Bool {
        guard isCloudEnabled, !trip.objectID.isTemporaryID else { return true }
        return container.canUpdateRecord(forManagedObjectWith: trip.objectID)
    }

    /// Names of people who accepted the share (excluding you).
    func participantNames(for trip: Trip) -> [String] {
        guard let share = share(for: trip) else { return [] }
        return share.participants
            .filter { $0.acceptanceStatus == .accepted && $0 != share.currentUserParticipant }
            .compactMap { participant in
                participant.userIdentity.nameComponents.map {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .short)
                }
            }
    }

    /// Joins a trip someone shared with you.
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        guard let sharedStore else { return }
        try await container.acceptShareInvitations(from: [metadata], into: sharedStore)
    }

    /// Leaves a trip shared with you (removes it from this device and your iCloud).
    func leave(_ trip: Trip) async throws {
        guard let sharedStore, let share = share(for: trip) else { return }
        try await container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: sharedStore)
    }
}

extension NSManagedObject {
    /// New objects must live in the same store as the trip they belong to — otherwise adding
    /// something to a trip that was shared with you would fail to save.
    func placeInSameStore(as owner: NSManagedObject) {
        guard let context = managedObjectContext,
              !owner.objectID.isTemporaryID,
              let store = owner.objectID.persistentStore else { return }
        context.assign(self, to: store)
    }
}
