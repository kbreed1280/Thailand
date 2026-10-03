import Foundation

/// Small per-device preferences (read in views with `@AppStorage`).
enum AppSettings {
    static let displayNameKey = "displayName"
    static let selectedTripKey = "selectedTripID"
    static let defaultDisplayName = "Me"

    /// Name recorded as "added by" / "edited by". Replaced by the iCloud name once sharing is on.
    static var displayName: String {
        let stored = UserDefaults.standard.string(forKey: displayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultDisplayName : stored
    }
}
