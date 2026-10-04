import Foundation

/// Small per-device preferences (read in views with `@AppStorage`).
enum AppSettings {
    static let displayNameKey = "displayName"
    static let selectedTripKey = "selectedTripID"
    static let defaultDisplayName = "Me"
    static let usernameKey = "username"
    static let avatarEmojiKey = "avatarEmoji"

    /// Profile photo, kept on this device (Application Support/avatar.jpg).
    static var avatarPhotoURL: URL {
        URL.applicationSupportDirectory.appending(path: "avatar.jpg")
    }

    /// Name recorded as "added by" / "edited by". Replaced by the iCloud name once sharing is on.
    static var displayName: String {
        let stored = UserDefaults.standard.string(forKey: displayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultDisplayName : stored
    }
}
