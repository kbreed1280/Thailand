import CoreLocation
import Foundation

/// Reorders a day's stops for the shortest trip: nearest neighbour, then 2-opt until no swap helps.
/// Straight-line distance is a good stand-in for walking/driving order inside a city. Pure and unit-tested.
enum RouteOptimizer {
    /// Distance in meters between two points (haversine).
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// Total length of visiting `points` in `order`, from `start` and to `end` when given.
    static func length(_ order: [Int], points: [CLLocationCoordinate2D], start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?) -> Double {
        var path = order.map { points[$0] }
        if let start { path.insert(start, at: 0) }
        if let end { path.append(end) }
        return zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// The best visiting order (indices into `points`). With no start, every stop is tried as the first one.
    static func order(points: [CLLocationCoordinate2D], start: CLLocationCoordinate2D? = nil, end: CLLocationCoordinate2D? = nil) -> [Int] {
        guard points.count > 2 || (points.count == 2 && (start != nil || end != nil)) else { return Array(points.indices) }
        let firsts: [Int?] = start == nil ? points.indices.map { $0 } : [nil]
        var best = Array(points.indices)
        var bestLength = length(best, points: points, start: start, end: end)
        for first in firsts {
            let candidate = twoOpt(nearestNeighbour(points: points, start: start, first: first), points: points, start: start, end: end)
            let candidateLength = length(candidate, points: points, start: start, end: end)
            if candidateLength < bestLength - 0.5 {
                best = candidate
                bestLength = candidateLength
            }
        }
        return best
    }

    private static func nearestNeighbour(points: [CLLocationCoordinate2D], start: CLLocationCoordinate2D?, first: Int?) -> [Int] {
        var remaining = Set(points.indices)
        var order: [Int] = []
        var current: CLLocationCoordinate2D
        if let first {
            order.append(first)
            remaining.remove(first)
            current = points[first]
        } else if let start {
            current = start
        } else {
            return Array(points.indices)
        }
        while !remaining.isEmpty {
            let next = remaining.min { distance(current, points[$0]) < distance(current, points[$1]) }!
            order.append(next)
            remaining.remove(next)
            current = points[next]
        }
        return order
    }

    private static func twoOpt(_ initial: [Int], points: [CLLocationCoordinate2D], start: CLLocationCoordinate2D?, end: CLLocationCoordinate2D?) -> [Int] {
        var order = initial
        var bestLength = length(order, points: points, start: start, end: end)
        var improved = true
        var passes = 0
        while improved && passes < 50 {
            improved = false
            passes += 1
            for i in 0..<(order.count - 1) {
                for j in (i + 1)..<order.count {
                    var candidate = order
                    candidate[i...j].reverse()
                    let candidateLength = length(candidate, points: points, start: start, end: end)
                    if candidateLength < bestLength - 0.5 {
                        order = candidate
                        bestLength = candidateLength
                        improved = true
                    }
                }
            }
        }
        return order
    }

    /// Fills the slots that held mappable stops with those stops in the optimized order; stops with no
    /// location (a "free time" note, say) keep their place in the day.
    static func merged<T>(all items: [T], hasLocation: (T) -> Bool, optimized: [T]) -> [T] {
        var queue = optimized[...]
        return items.map { item in
            hasLocation(item) ? (queue.popFirst() ?? item) : item
        }
    }
}

/// Trip budget: planned vs. spent, overall and per category. Amounts are in the trip's local money.
enum BudgetMath {
    struct Line: Equatable {
        var category: ExpenseCategory
        var budget: Double
        var spent: Double
        var remaining: Double { budget - spent }
        var fraction: Double { budget > 0 ? spent / budget : 0 }
    }

    struct Summary: Equatable {
        var budget: Double
        var spent: Double
        /// Costs typed on itinerary items that aren't done yet (the rest of the plan).
        var planned: Double
        var lines: [Line]
        var remaining: Double { budget - spent }
        var fraction: Double { budget > 0 ? spent / budget : 0 }
        /// Spent plus what's still planned.
        var projected: Double { spent + planned }
    }

    /// "food=3000\nlodging=12000" ⇄ dictionary.
    static func parse(_ text: String?) -> [ExpenseCategory: Double] {
        var result: [ExpenseCategory: Double] = [:]
        for line in (text ?? "").split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let category = ExpenseCategory(rawValue: String(parts[0])),
                  let amount = Double(parts[1]), amount > 0 else { continue }
            result[category] = amount
        }
        return result
    }

    static func format(_ budgets: [ExpenseCategory: Double]) -> String {
        ExpenseCategory.allCases.compactMap { category in
            guard let amount = budgets[category], amount > 0 else { return nil }
            return "\(category.rawValue)=\(amount)"
        }.joined(separator: "\n")
    }

    /// Itinerary item categories counted against expense categories for the "planned" total.
    static func expenseCategory(for item: ItemCategory) -> ExpenseCategory {
        switch item {
        case .meal: .food
        case .hotel: .lodging
        case .transport: .transport
        case .activity, .place: .activities
        }
    }

    static func summary(total: Double, perCategory: [ExpenseCategory: Double],
                        expenses: [(category: ExpenseCategory, amount: Double)],
                        plannedCosts: [Double]) -> Summary {
        let spentBy = Dictionary(grouping: expenses, by: \.category).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let spent = expenses.reduce(0) { $0 + $1.amount }
        let lines = ExpenseCategory.allCases.compactMap { category -> Line? in
            let budget = perCategory[category] ?? 0
            let used = spentBy[category] ?? 0
            guard budget > 0 || used > 0 else { return nil }
            return Line(category: category, budget: budget, spent: used)
        }
        // With no overall budget, the category budgets add up to it.
        let overall = total > 0 ? total : perCategory.values.reduce(0, +)
        return Summary(budget: overall, spent: spent, planned: plannedCosts.reduce(0, +), lines: lines)
    }
}

/// Custom lists beside the Wish List ("Restaurants", "Things to do"). Pure helpers.
enum TripLists {
    static func names(stored: String?, itemLists: [String]) -> [String] {
        var seen = Set<String>()
        let stored = (stored ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return (stored + itemLists).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func adding(_ name: String, to stored: String?) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = names(stored: stored, itemLists: [])
        guard !clean.isEmpty, !current.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else {
            return current.joined(separator: "\n")
        }
        return (current + [clean]).joined(separator: "\n")
    }

    static func removing(_ name: String, from stored: String?) -> String {
        names(stored: stored, itemLists: []).filter { $0 != name }.joined(separator: "\n")
    }

    static func renaming(_ old: String, to new: String, in stored: String?) -> String {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return names(stored: stored, itemLists: []).joined(separator: "\n") }
        return names(stored: stored, itemLists: []).map { $0 == old ? clean : $0 }.joined(separator: "\n")
    }

    /// Suggested names offered when making a list.
    static let suggestions = ["Restaurants", "Things to do", "Cafés", "Nightlife", "Shopping", "Day trips"]
}

/// KML for Google My Maps: one folder per day (plus lists), one placemark per stop.
enum MapExport {
    struct Place {
        var name: String
        var notes: String
        var latitude: Double
        var longitude: Double
    }

    static func kml(title: String, folders: [(name: String, places: [Place])]) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
        <name>\(esc(title))</name>

        """
        for folder in folders where !folder.places.isEmpty {
            out += "<Folder><name>\(esc(folder.name))</name>\n"
            for (index, place) in folder.places.enumerated() {
                out += "<Placemark><name>\(index + 1). \(esc(place.name))</name>"
                if !place.notes.isEmpty { out += "<description>\(esc(place.notes))</description>" }
                out += "<Point><coordinates>\(place.longitude),\(place.latitude),0</coordinates></Point></Placemark>\n"
            }
            out += "</Folder>\n"
        }
        out += "</Document>\n</kml>\n"
        return out
    }
}
