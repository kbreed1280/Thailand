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
