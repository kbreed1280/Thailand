import UIKit
import CloudKit
import CoreData

/// Presents Apple's sharing sheet for a trip and handles accepting invitations.
@MainActor
enum TripSharing {
    enum SharingError: LocalizedError {
        case cloudDisabled
        case notSaved

        var errorDescription: String? {
            switch self {
            case .cloudDisabled: "Sharing needs iCloud. Sign in to iCloud in Settings and turn on iCloud Drive."
            case .notSaved: "Save the trip first, then try sharing again."
            }
        }
    }

    private static let delegate = SharingControllerDelegate()

    /// Creates the share if needed, then shows `UICloudSharingController` where you can invite
    /// people by Messages, Mail or link, change their permission (read-only / can edit) or remove them.
    static func presentShareSheet(for trip: Trip) async throws {
        let persistence = PersistenceController.shared
        guard persistence.isCloudEnabled, let privateStore = persistence.privateStore else { throw SharingError.cloudDisabled }
        persistence.save()
        guard !trip.objectID.isTemporaryID else { throw SharingError.notSaved }

        let share: CKShare
        if let existing = persistence.share(for: trip) {
            share = existing
        } else {
            let (_, newShare, _) = try await persistence.container.share([trip], to: nil)
            newShare[CKShare.SystemFieldKey.title] = trip.displayName
            newShare.publicPermission = .none
            _ = try await persistence.container.persistUpdatedShare(newShare, in: privateStore)
            share = newShare
        }

        let controller = UICloudSharingController(share: share, container: persistence.cloudKitContainer)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite, .allowReadOnly]
        controller.delegate = delegate
        controller.modalPresentationStyle = .formSheet
        topViewController()?.present(controller, animated: true)
    }

    // MARK: Accepting invitations

    static let pendingShareKey = "pendingSharedTripRecordName"

    /// Called when someone taps an invitation link and the app opens.
    static func accept(_ metadata: CKShare.Metadata) async {
        do {
            try await PersistenceController.shared.acceptShare(metadata)
            // The trip arrives from iCloud shortly after; TripTabView selects it when it does.
            UserDefaults.standard.set(metadata.share.recordID.recordName, forKey: pendingShareKey)
            NotificationCenter.default.post(name: .didAcceptTripShare, object: nil)
        } catch {
            print("Accepting share failed: \(error)")
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

extension Notification.Name {
    static let didAcceptTripShare = Notification.Name("didAcceptTripShare")
}

@MainActor
final class SharingControllerDelegate: NSObject, UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Saving share failed: \(error)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        csc.share?[CKShare.SystemFieldKey.title] as? String ?? "Thailand Trip"
    }

    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        UIImage(systemName: "sun.horizon.fill")?
            .withTintColor(UIColor(hex: "#F4821C"), renderingMode: .alwaysOriginal)
            .pngData()
    }
}

/// Fills in your name from iCloud (used for "added by") if you haven't typed one.
enum IdentityService {
    static func refreshDisplayName() async {
        let stored = UserDefaults.standard.string(forKey: AppSettings.displayNameKey) ?? ""
        guard stored.isEmpty, PersistenceController.shared.isCloudEnabled else { return }
        let container = PersistenceController.shared.cloudKitContainer
        guard let recordID = try? await container.userRecordID(),
              let participant = try? await container.shareParticipant(forUserRecordID: recordID),
              let components = participant.userIdentity.nameComponents else { return }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
        if !name.isEmpty {
            UserDefaults.standard.set(name, forKey: AppSettings.displayNameKey)
        }
    }
}
