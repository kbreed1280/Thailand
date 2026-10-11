import ActivityKit
import Foundation

/// Today's plan on the Lock Screen and in the Dynamic Island: the next stop and the one after.
/// Started from the Today card; refreshed whenever the app comes to the foreground.
@MainActor
final class DayPlanActivityController: ObservableObject {
    static let shared = DayPlanActivityController()

    @Published private(set) var liveDayID: String?

    private var current: Activity<DayPlanActivityAttributes>? { Activity<DayPlanActivityAttributes>.activities.first }

    init() { liveDayID = Activity<DayPlanActivityAttributes>.activities.first?.attributes.dayID }

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func isLive(_ day: Day) -> Bool { liveDayID != nil && liveDayID == day.uuid?.uuidString }

    /// Stops still ahead today: anything not done whose time (plus its length) hasn't passed.
    static func upcoming(in day: Day, now: Date = .now) -> [Item] {
        day.sortedItems.filter { item in
            guard item.status != .done else { return false }
            guard let time = item.time else { return true }
            return time.addingTimeInterval(Double(max(item.durationMinutes, 30)) * 60) > now
        }
    }

    static func state(for day: Day, now: Date = .now) -> DayPlanActivityAttributes.ContentState {
        let ahead = upcoming(in: day, now: now)
        func stop(_ item: Item?) -> DayPlanActivityAttributes.Stop? {
            item.map { .init(title: $0.displayTitle, time: $0.time, symbol: $0.category.systemImage, address: $0.address ?? "") }
        }
        return .init(next: stop(ahead.first), after: stop(ahead.dropFirst().first), remaining: max(0, ahead.count - 1), updatedAt: now)
    }

    func start(_ day: Day, in trip: Trip) {
        guard isAvailable, let id = day.uuid?.uuidString else { return }
        if let current { Task { await current.end(nil, dismissalPolicy: .immediate) } }
        let attributes = DayPlanActivityAttributes(tripName: trip.displayName, dayTitle: "Day \(day.number)", dayID: id)
        let content = ActivityContent(state: Self.state(for: day), staleDate: Date().addingTimeInterval(2 * 3600))
        if (try? Activity.request(attributes: attributes, content: content, pushType: nil)) != nil { liveDayID = id }
    }

    func stop() {
        for activity in Activity<DayPlanActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        liveDayID = nil
    }

    /// Moves the Live Activity on to the next stop (or ends it when the day is over).
    func refresh(trip: Trip?) {
        guard let current, let trip,
              let day = trip.sortedDays.first(where: { $0.uuid?.uuidString == current.attributes.dayID }) else { return }
        let state = Self.state(for: day)
        if state.next == nil {
            Task { await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(3600))) }
            liveDayID = nil
        } else {
            Task { await current.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(2 * 3600))) }
        }
    }
}
