import ActivityKit
import Foundation

/// Shared with the ThailandWidgets extension (an identical copy lives in ThailandWidgets/).
/// Keep both files the same: ActivityKit matches the app and widget by this type.
struct DayPlanActivityAttributes: ActivityAttributes {
    struct Stop: Codable, Hashable {
        var title: String
        var time: Date?
        var symbol: String
        var address: String
    }

    struct ContentState: Codable, Hashable {
        var next: Stop?
        var after: Stop?
        /// Stops left today after `next`.
        var remaining: Int
        var updatedAt: Date
    }

    var tripName: String
    var dayTitle: String
    var dayID: String
}
