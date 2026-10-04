import CoreLocation
import Foundation

/// Turns saved spots into day plans: groups nearby spots into the same day (so you aren't
/// crossing Bangkok traffic three times), orders each day around Thai heat (coffee and temples
/// in the morning, indoor stops through the midday heat, rooftops and night markets after
/// sunset) and walks the shortest path within each part of the day. Pure and unit-tested.
enum AutoPlanner {
    enum Pace: String, CaseIterable, Identifiable {
        case relaxed, balanced, packed
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var stopsPerDay: Int {
            switch self {
            case .relaxed: 3
            case .balanced: 5
            case .packed: 7
            }
        }
    }

    enum Vibe: String, CaseIterable, Identifiable {
        case foodie, culture, nightlife, chill, adventure, shopping
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var emoji: String {
            switch self {
            case .foodie: "🍜"
            case .culture: "🛕"
            case .nightlife: "🍸"
            case .chill: "🌴"
            case .adventure: "🧗"
            case .shopping: "🛍️"
            }
        }
        /// Apple Maps searches used to fill a day with something that fits the trip's vibe.
        var fillQueries: [String] {
            switch self {
            case .foodie: ["street food", "local restaurant", "night market"]
            case .culture: ["temple", "museum", "historic site"]
            case .nightlife: ["rooftop bar", "cocktail bar", "night market"]
            case .chill: ["café", "spa", "park"]
            case .adventure: ["viewpoint", "park", "boat tour"]
            case .shopping: ["market", "shopping mall", "boutique"]
            }
        }
    }

    /// Part of the day a stop fits best, from the category and (for outdoor sights) the heat.
    enum Slot: Int, Comparable, CaseIterable {
        case morning, midday, afternoon, evening
        static func < (a: Slot, b: Slot) -> Bool { a.rawValue < b.rawValue }

        var startHour: Int {
            switch self {
            case .morning: 8
            case .midday: 12
            case .afternoon: 15
            case .evening: 18
            }
        }
    }

    struct Stop: Equatable, Identifiable {
        let id: UUID
        let name: String
        let coordinate: CLLocationCoordinate2D
        let category: SpotCategory
        /// A gap filler found for the trip's vibe rather than one of your saved spots.
        var isSuggestion = false

        static func == (a: Stop, b: Stop) -> Bool { a.id == b.id }
    }

    struct PlannedStop: Equatable, Identifiable {
        let stop: Stop
        let start: Date
        let durationMinutes: Int
        var id: UUID { stop.id }
    }

    struct DayPlan: Equatable {
        let date: Date
        var stops: [PlannedStop]
        /// What the day is missing (e.g. a meal), for gap fill.
        var gaps: [SpotCategory]
    }

    struct Plan: Equatable {
        var days: [DayPlan]
        /// Spots that didn't fit at this pace.
        var leftOver: [Stop]
    }

    // MARK: Plan

    /// - Parameters:
    ///   - hotDays: days whose midday heat index is dangerous; outdoor sights move to the morning.
    static func plan(_ stops: [Stop], dates: [Date], pace: Pace, hotDays: Set<Date> = [], calendar: Calendar = .current) -> Plan {
        guard !dates.isEmpty, !stops.isEmpty else { return Plan(days: dates.map { DayPlan(date: $0, stops: [], gaps: []) }, leftOver: stops) }
        let capacity = pace.stopsPerDay
        let clusters = cluster(stops, into: min(dates.count, Int((Double(stops.count) / Double(capacity)).rounded(.up))), capacity: capacity)

        var leftOver: [Stop] = []
        var days: [DayPlan] = []
        for (index, date) in dates.enumerated() {
            var group = index < clusters.count ? clusters[index] : []
            if group.count > capacity {
                leftOver += group[capacity...]
                group = Array(group[..<capacity])
            }
            let hot = hotDays.contains { calendar.isDate($0, inSameDayAs: date) }
            let ordered = order(group, hot: hot)
            days.append(DayPlan(date: date, stops: schedule(ordered, on: date, hot: hot, calendar: calendar),
                                gaps: gaps(in: group, capacity: capacity)))
        }
        return Plan(days: days, leftOver: leftOver)
    }

    // MARK: Clustering (k-means with farthest-first seeds, capped per day)

    static func cluster(_ stops: [Stop], into k: Int, capacity: Int) -> [[Stop]] {
        guard k > 1 else { return [stops] }
        // Farthest-first seeding: deterministic, spreads days across the city.
        let middle = centroid(stops)
        var centers = [stops.max { distance($0.coordinate, middle) < distance($1.coordinate, middle) }!.coordinate]
        while centers.count < k {
            let next = stops.max { a, b in
                centers.map { distance(a.coordinate, $0) }.min()! < centers.map { distance(b.coordinate, $0) }.min()!
            }!
            centers.append(next.coordinate)
        }

        var groups: [[Stop]] = []
        for _ in 0..<12 {
            groups = Array(repeating: [], count: k)
            // Assign closest-first so a day that fills up spills its farthest spots to the next-best day.
            let ranked = stops.map { stop in (stop, centers.indices.sorted { distance(stop.coordinate, centers[$0]) < distance(stop.coordinate, centers[$1]) }) }
                .sorted { distance($0.0.coordinate, centers[$0.1[0]]) < distance($1.0.coordinate, centers[$1.1[0]]) }
            for (stop, preferences) in ranked {
                let target = preferences.first { groups[$0].count < capacity } ?? preferences[0]
                groups[target].append(stop)
            }
            let newCenters = groups.enumerated().map { $1.isEmpty ? centers[$0] : centroid($1) }
            if zip(newCenters, centers).allSatisfy({ distance($0, $1) < 1 }) { break }
            centers = newCenters
        }
        // Busiest areas first, so the opening days are the full ones.
        return groups.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    // MARK: Ordering within a day

    static func slot(for category: SpotCategory, hot: Bool) -> Slot {
        switch category {
        case .brew: .morning
        case .explore: .morning          // temples & outdoor sights before the heat
        case .eat: .midday
        case .vibe: hot ? .midday : .afternoon // shops, spas, malls: indoor through the heat
        case .go: .afternoon
        case .sip: .evening
        }
    }

    static func order(_ stops: [Stop], hot: Bool) -> [Stop] {
        // A second meal goes to dinner.
        // At most two sights before lunch; the rest go to late afternoon as it cools.
        var meals = 0, morningSights = 0
        let slotted: [(Stop, Slot)] = stops.map { stop in
            var s = slot(for: stop.category, hot: hot)
            if stop.category == .eat {
                meals += 1
                if meals > 1 { s = .evening }
            }
            if stop.category == .explore {
                morningSights += 1
                if morningSights > 2 { s = .afternoon }
            }
            return (stop, s)
        }
        var result: [Stop] = []
        var position: CLLocationCoordinate2D?
        for s in Slot.allCases {
            var remaining = slotted.filter { $0.1 == s }.map(\.0)
            while !remaining.isEmpty {
                let next = position.map { p in remaining.min { distance($0.coordinate, p) < distance($1.coordinate, p) }! } ?? remaining[0]
                result.append(next)
                position = next.coordinate
                remaining.removeAll { $0 == next }
            }
        }
        return result
    }

    static func duration(for category: SpotCategory) -> Int {
        switch category {
        case .brew: 45
        case .eat: 75
        case .sip: 90
        case .vibe: 90
        case .explore: 90
        case .go: 60
        }
    }

    /// Start times: each stop begins no earlier than its slot, after the previous stop plus travel
    /// (walking pace for short hops, taxi pace for long ones).
    static func schedule(_ stops: [Stop], on date: Date, hot: Bool, calendar: Calendar) -> [PlannedStop] {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        var planned: [PlannedStop] = []
        var clock = at(9)
        for (i, stop) in stops.enumerated() {
            let s = slot(for: stop.category, hot: hot)
            var earliest = s == .morning ? at(stop.category == .brew ? 8 : 9) : at(s.startHour)
            if stop.category == .eat, planned.contains(where: { $0.stop.category == .eat }) { earliest = at(18, 30) }
            if i > 0 { clock = clock.addingTimeInterval(travelSeconds(from: stops[i - 1].coordinate, to: stop.coordinate)) }
            let start = i == 0 ? earliest : ScheduleMath.roundedUpToFiveMinutes(max(clock, earliest))
            let minutes = duration(for: stop.category)
            planned.append(PlannedStop(stop: stop, start: start, durationMinutes: minutes))
            clock = start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        return planned
    }

    static func travelSeconds(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> TimeInterval {
        let meters = distance(a, b) * 1.3 // streets aren't straight
        return meters < 1_500 ? meters / 1.2 : 600 + meters / 5.5 // walk ≈ 4.3 km/h; taxi ≈ 20 km/h + 10 min to hail
    }

    static func gaps(in stops: [Stop], capacity: Int) -> [SpotCategory] {
        guard stops.count < capacity else { return [] }
        var missing: [SpotCategory] = []
        if !stops.contains(where: { $0.category == .eat }) { missing.append(.eat) }
        if stops.count + missing.count < capacity, !stops.contains(where: { $0.category == .explore }) { missing.append(.explore) }
        return missing
    }

    // MARK: Shortest route (Sidequests)

    /// Visiting order that keeps total distance short: nearest-neighbour from `start` (or the
    /// first stop), then 2-opt to untangle crossings. Open path, no return to start.
    static func shortestRoute(_ stops: [Stop], from start: CLLocationCoordinate2D? = nil) -> [Stop] {
        guard stops.count > 2 else { return stops }
        var remaining = stops
        var route: [Stop] = []
        var here = start ?? stops[0].coordinate
        while !remaining.isEmpty {
            let i = remaining.indices.min { distance(remaining[$0].coordinate, here) < distance(remaining[$1].coordinate, here) }!
            here = remaining[i].coordinate
            route.append(remaining.remove(at: i))
        }
        func length(_ r: [Stop]) -> Double {
            var total = start.map { distance($0, r[0].coordinate) } ?? 0
            for k in 1..<r.count { total += distance(r[k - 1].coordinate, r[k].coordinate) }
            return total
        }
        var improved = true
        var best = length(route)
        while improved {
            improved = false
            for i in 0..<(route.count - 1) {
                for j in (i + 1)..<route.count {
                    var candidate = route
                    candidate[i...j].reverse()
                    let l = length(candidate)
                    if l + 1 < best { route = candidate; best = l; improved = true }
                }
            }
        }
        return route
    }

    static func routeLength(_ stops: [Stop]) -> CLLocationDistance {
        zip(stops, stops.dropFirst()).map { distance($0.coordinate, $1.coordinate) }.reduce(0, +)
    }

    // MARK: Geometry

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func centroid(_ stops: [Stop]) -> CLLocationCoordinate2D {
        let n = Double(max(stops.count, 1))
        return CLLocationCoordinate2D(latitude: stops.map(\.coordinate.latitude).reduce(0, +) / n,
                                      longitude: stops.map(\.coordinate.longitude).reduce(0, +) / n)
    }
}
