import Foundation

/// Pure timing helpers for the day timeline and route planner (unit-tested).
enum ScheduleMath {
    /// Minutes to arrive before the next stop's start time.
    static let defaultBufferMinutes = 5

    /// How many minutes late you'd be for `nextStart` after finishing at `previousEnd`,
    /// travelling `travelSeconds` and keeping a buffer. 0 means you're fine.
    static func minutesLate(previousEnd: Date, travelSeconds: TimeInterval, bufferMinutes: Int = defaultBufferMinutes, nextStart: Date) -> Int {
        let arrival = previousEnd.addingTimeInterval(travelSeconds + TimeInterval(bufferMinutes * 60))
        let late = arrival.timeIntervalSince(nextStart)
        return late > 0 ? Int((late / 60).rounded(.up)) : 0
    }

    /// New start times after reordering: keeps the first start, each stop's duration, and the
    /// travel time between consecutive stops. `travelSeconds[i]` is the trip from stop i to i+1.
    static func retimedStarts(firstStart: Date, durationsMinutes: [Int], travelSeconds: [TimeInterval], bufferMinutes: Int = defaultBufferMinutes) -> [Date] {
        guard !durationsMinutes.isEmpty else { return [] }
        var starts = [firstStart]
        for index in 1..<durationsMinutes.count {
            let previousEnd = starts[index - 1].addingTimeInterval(TimeInterval(max(durationsMinutes[index - 1], 0) * 60))
            let travel = index - 1 < travelSeconds.count ? travelSeconds[index - 1] : 0
            starts.append(roundedUpToFiveMinutes(previousEnd.addingTimeInterval(travel + TimeInterval(bufferMinutes * 60))))
        }
        return starts
    }

    static func roundedUpToFiveMinutes(_ date: Date) -> Date {
        let interval = 5.0 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / interval).rounded(.up) * interval)
    }

    /// "12 min" / "1 h 5 min"
    static func durationText(seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
