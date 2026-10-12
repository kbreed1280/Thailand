import CloudKit
import CoreData
import Foundation

/// Debug-only: records iCloud sync events and sharing errors to Documents/sync.log, so a
/// development install's sync problems can be read off the device.
enum SyncLog {
    static var url: URL { URL.documentsDirectory.appending(path: "sync.log") }

    static func write(_ line: String) {
        #if DEBUG
        let stamp = ISO8601DateFormatter().string(from: .now)
        let data = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
        #endif
    }

    /// Asks iCloud about every trip share: does it exist on the server, its link, and who is on it.
    @MainActor
    static func checkShares() async {
        #if DEBUG
        let persistence = PersistenceController.shared
        guard persistence.isCloudEnabled else { return }
        let trips = (try? persistence.viewContext.fetch(NSFetchRequest<Trip>(entityName: "Trip"))) ?? []
        for trip in trips {
            guard let local = persistence.share(for: trip) else { continue }
            let db = persistence.isSharedWithMe(trip) ? persistence.cloudKitContainer.sharedCloudDatabase : persistence.cloudKitContainer.privateCloudDatabase
            do {
                guard let server = try await db.record(for: local.recordID) as? CKShare else {
                    write("check \(trip.displayName): server record isn't a share"); continue
                }
                let people = server.participants.map { p in
                    let who = p.userIdentity.lookupInfo?.emailAddress ?? p.userIdentity.lookupInfo?.phoneNumber
                        ?? p.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? "?"
                    let status = switch p.acceptanceStatus { case .accepted: "accepted"; case .pending: "pending"; case .removed: "removed"; default: "unknown" }
                    let role = p.role == .owner ? "owner" : "participant"
                    return "\(who)[\(role),\(status),\(p.permission == .readWrite ? "rw" : "ro")]"
                }
                write("check \(trip.displayName): url=\(server.url?.absoluteString ?? "nil") public=\(server.publicPermission.rawValue) people=\(people)")
            } catch {
                write("check \(trip.displayName): server error \(error)")
            }
        }
        #endif
    }

    static func observe(_ container: NSPersistentCloudKitContainer) {
        #if DEBUG
        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: container, queue: nil) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            let kind = switch event.type { case .setup: "setup"; case .import: "import"; case .export: "export"; @unknown default: "other" }
            let store = event.storeIdentifier.prefix(8)
            write("\(kind) store=\(store) ok=\(event.succeeded)\(event.error.map { " error=\($0)" } ?? "")")
        }
        #endif
    }
}
