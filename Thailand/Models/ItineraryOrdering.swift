import Foundation

/// Pure ordering helpers for the itinerary, kept free of Core Data so they're easy to unit test.
enum ItineraryOrdering {
    /// Places `id` immediately before `target`, or at the end when `target` is nil or missing.
    /// `id` is removed from its old position first, so this handles both reordering within a
    /// list and moving an item in from another list.
    static func inserting<ID: Equatable>(_ id: ID, before target: ID?, in list: [ID]) -> [ID] {
        var result = list.filter { $0 != id }
        if let target, target != id, let index = result.firstIndex(of: target) {
            result.insert(id, at: index)
        } else {
            result.append(id)
        }
        return result
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without depending on SwiftUI.
    static func moving<T>(_ list: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        let valid = source.filter { $0 >= 0 && $0 < list.count }
        guard !valid.isEmpty else { return list }
        let moved = valid.map { list[$0] }
        var result = list
        for index in valid.sorted(by: >) {
            result.remove(at: index)
        }
        let removedBefore = valid.filter { $0 < destination }.count
        let insertAt = min(max(destination - removedBefore, 0), result.count)
        result.insert(contentsOf: moved, at: insertAt)
        return result
    }

    /// Every calendar day from `start` through `end` (inclusive), as start-of-day dates.
    /// Capped at `limit` days so a typo in the year can't create thousands of days.
    static func dayDates(from start: Date, to end: Date, calendar: Calendar = .current, limit: Int = 90) -> [Date] {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        var dates: [Date] = []
        var current = first
        while current <= last && dates.count < limit {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}
