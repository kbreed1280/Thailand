import Foundation
import ActivityKit

/// Shared with the ThailandWidgets extension (an identical copy lives in ThailandWidgets/).
/// Keep both files the same: ActivityKit matches the app and widget by this type.
struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var statusText: String
        var departure: Date
        var arrival: Date?
        var delayMinutes: Int
        var terminal: String?
        var gate: String?
        var baggageBelt: String?
        var isCanceled: Bool
        var hasLanded: Bool
        var updatedAt: Date
    }

    var flightID: String
    var number: String
    var from: String
    var to: String
    var airline: String
}
