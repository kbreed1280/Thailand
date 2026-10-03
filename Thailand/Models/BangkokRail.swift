import Foundation
import CoreLocation

// MARK: - Network data (bundled BangkokRail.json, from OpenStreetMap)

struct RailStation: Codable, Hashable, Identifiable {
    let code: String
    let en: String
    let th: String
    let lat: Double
    let lon: Double

    var id: String { code }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

struct RailLine: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let short: String
    let system: String
    let color: String
    let stations: [RailStation]
    var extraLinks: [[String]]?
    var removeLinks: [[String]]?

    /// Rough fares in baht: (minimum, per stop, maximum). Real fares change; shown as estimates.
    var fareModel: (base: Double, perStop: Double, cap: Double) {
        switch id {
        case "bts-sukhumvit", "bts-silom", "bts-gold": (17, 3, 47)
        case "mrt-blue": (17, 2, 45)
        case "mrt-purple": (14, 2, 42)
        case "mrt-yellow", "mrt-pink": (15, 2.5, 45)
        case "arl": (15, 5, 45)
        default: (12, 3, 42)
        }
    }

    /// Lines you can change between without leaving the paid area (one fare).
    var fareGroup: String {
        switch system {
        case "BTS": "BTS"
        default: id
        }
    }
}

/// A place in the network: one station on one line (interchanges are several nodes).
struct RailNode: Hashable {
    let lineIndex: Int
    let stationIndex: Int
}

// MARK: - Route result

struct RailRide: Identifiable, Hashable {
    let id = UUID()
    let line: RailLine
    let stations: [RailStation]

    var from: RailStation { stations.first! }
    var to: RailStation { stations.last! }
    var stops: Int { max(stations.count - 1, 0) }

    /// The station after boarding, to make sure you take the right platform.
    var nextStop: RailStation? { stations.count > 1 ? stations[1] : nil }

    /// End of the line in the travel direction ("toward Kheha").
    var terminus: RailStation {
        guard let a = line.stations.firstIndex(of: from), let b = line.stations.firstIndex(of: to) else { return to }
        // The Blue Line loops through Tha Phra, so "end of the line" is misleading there.
        if line.id == "mrt-blue" { return to }
        return b >= a ? line.stations.last! : line.stations.first!
    }

    static func == (lhs: RailRide, rhs: RailRide) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct RailJourney: Hashable {
    let walkToStationMeters: Double
    let rides: [RailRide]
    let walkFromStationMeters: Double
    let totalMinutes: Double
    let fareTHB: Double

    var boardAt: RailStation { rides.first!.from }
    var getOffAt: RailStation { rides.last!.to }
    var transfers: Int { max(rides.count - 1, 0) }
    var walkToMinutes: Double { BangkokRail.walkMinutes(walkToStationMeters) }
    var walkFromMinutes: Double { BangkokRail.walkMinutes(walkFromStationMeters) }
}

// MARK: - Network + router

final class BangkokRail {
    static let shared = BangkokRail()

    let lines: [RailLine]
    let attribution: String
    private var neighbors: [RailNode: [(RailNode, Double)]] = [:]

    // Timing assumptions (minutes).
    static let minutesPerStop: [String: Double] = ["arl": 3.2, "srt-dark-red": 3.5]
    static let defaultMinutesPerStop = 2.3
    static let waitMinutes = 4.0
    static let transferRadius: CLLocationDistance = 350
    static let walkMetersPerMinute = 70.0
    /// Street walking is longer than a straight line.
    static let detourFactor = 1.3

    static func walkMinutes(_ meters: Double) -> Double { meters / walkMetersPerMinute }

    /// Greater Bangkok, where the rail network is useful.
    static func covers(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (13.5...14.05).contains(coordinate.latitude) && (100.3...100.9).contains(coordinate.longitude)
    }

    private struct File: Codable {
        let source: String
        let lines: [RailLine]
    }

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "BangkokRail", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            lines = file.lines
            attribution = "Station data © OpenStreetMap contributors"
        } else {
            lines = []
            attribution = ""
        }
        buildGraph()
    }

    var allStations: [(station: RailStation, line: RailLine)] {
        lines.flatMap { line in line.stations.map { ($0, line) } }
    }

    /// Unique stations by name (interchanges listed once), with every line serving them.
    var stationDirectory: [(station: RailStation, lines: [RailLine])] {
        var order: [String] = []
        var groups: [String: (RailStation, [RailLine])] = [:]
        for (station, line) in allStations {
            let key = station.en.lowercased()
            if var existing = groups[key] {
                if !existing.1.contains(line) { existing.1.append(line) }
                groups[key] = existing
            } else {
                groups[key] = (station, [line])
                order.append(key)
            }
        }
        return order.compactMap { groups[$0] }.sorted { $0.0.en < $1.0.en }
    }

    func lines(serving station: RailStation) -> [RailLine] {
        lines.filter { line in line.stations.contains { $0.en == station.en || $0.code == station.code } }
    }

    private func station(_ node: RailNode) -> RailStation { lines[node.lineIndex].stations[node.stationIndex] }

    private func node(code: String, lineIndex: Int) -> RailNode? {
        lines[lineIndex].stations.firstIndex { $0.code == code }.map { RailNode(lineIndex: lineIndex, stationIndex: $0) }
    }

    private func link(_ a: RailNode, _ b: RailNode, _ minutes: Double) {
        neighbors[a, default: []].append((b, minutes))
        neighbors[b, default: []].append((a, minutes))
    }

    private func buildGraph() {
        for (li, line) in lines.enumerated() {
            let perStop = Self.minutesPerStop[line.id] ?? Self.defaultMinutesPerStop
            let removed = Set((line.removeLinks ?? []).map { $0.sorted().joined(separator: "-") })
            for si in 0..<max(line.stations.count - 1, 0) {
                let key = [line.stations[si].code, line.stations[si + 1].code].sorted().joined(separator: "-")
                if removed.contains(key) { continue }
                link(RailNode(lineIndex: li, stationIndex: si), RailNode(lineIndex: li, stationIndex: si + 1), perStop)
            }
            for pair in line.extraLinks ?? [] where pair.count == 2 {
                if let a = node(code: pair[0], lineIndex: li), let b = node(code: pair[1], lineIndex: li) {
                    link(a, b, perStop)
                }
            }
        }
        // Interchanges: stations on different lines within a short walk.
        let all = lines.indices.flatMap { li in lines[li].stations.indices.map { RailNode(lineIndex: li, stationIndex: $0) } }
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] where a.lineIndex != b.lineIndex {
                let meters = station(a).location.distance(from: station(b).location)
                if meters <= Self.transferRadius {
                    link(a, b, Self.walkMinutes(meters * Self.detourFactor) + Self.waitMinutes)
                }
            }
        }
    }

    /// The closest stations to a point (one entry per station name), nearest first.
    func nearestStations(to coordinate: CLLocationCoordinate2D, limit: Int = 3, within maxMeters: Double = 3000) -> [(station: RailStation, lines: [RailLine], meters: Double)] {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var best: [String: (RailStation, [RailLine], Double)] = [:]
        for (station, line) in allStations {
            let meters = here.distance(from: station.location)
            guard meters <= maxMeters else { continue }
            let key = station.en.lowercased()
            if var existing = best[key] {
                if !existing.1.contains(line) { existing.1.append(line) }
                existing.2 = min(existing.2, meters)
                best[key] = existing
            } else {
                best[key] = (station, [line], meters)
            }
        }
        return best.values.sorted { $0.2 < $1.2 }.prefix(limit).map { ($0.0, $0.1, $0.2) }
    }

    /// Best rail journey between two points, or nil when rail doesn't help
    /// (no station within walking distance, or walking is about as fast).
    func journey(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, maxWalkMeters: Double = 1600) -> RailJourney? {
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let end = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        // Under a kilometre, walking beats queuing for a ticket and the platform.
        guard start.distance(from: end) >= 1000 else { return nil }

        var dist: [RailNode: Double] = [:]
        var previous: [RailNode: RailNode] = [:]
        var startWalk: [RailNode: Double] = [:]
        var queue: [RailNode] = []

        for li in lines.indices {
            for si in lines[li].stations.indices {
                let node = RailNode(lineIndex: li, stationIndex: si)
                let meters = start.distance(from: station(node).location) * Self.detourFactor
                if meters <= maxWalkMeters {
                    dist[node] = Self.walkMinutes(meters) + Self.waitMinutes
                    startWalk[node] = meters
                    queue.append(node)
                }
            }
        }
        guard !queue.isEmpty else { return nil }

        // Dijkstra (the graph is small: ~200 nodes).
        var done = Set<RailNode>()
        while let current = queue.min(by: { dist[$0, default: .infinity] < dist[$1, default: .infinity] }) {
            queue.removeAll { $0 == current }
            if done.contains(current) { continue }
            done.insert(current)
            let base = dist[current, default: .infinity]
            for (next, cost) in neighbors[current] ?? [] where !done.contains(next) {
                let candidate = base + cost
                if candidate < dist[next, default: .infinity] {
                    dist[next] = candidate
                    previous[next] = current
                    if !queue.contains(next) { queue.append(next) }
                }
            }
        }

        // Pick the exit station that minimizes ride + final walk.
        var bestExit: RailNode?
        var bestTotal = Double.infinity
        var bestExitWalk = 0.0
        for (node, minutes) in dist {
            let meters = end.distance(from: station(node).location) * Self.detourFactor
            guard meters <= maxWalkMeters else { continue }
            let total = minutes + Self.walkMinutes(meters)
            if total < bestTotal {
                bestTotal = total
                bestExit = node
                bestExitWalk = meters
            }
        }
        guard let exit = bestExit else { return nil }

        var path = [exit]
        while let p = previous[path[0]] { path.insert(p, at: 0) }
        guard let first = path.first, let walkIn = startWalk[first] else { return nil }

        // Split the path into rides (consecutive nodes on the same line).
        var rides: [RailRide] = []
        var currentLine = first.lineIndex
        var segment: [RailStation] = []
        for node in path {
            if node.lineIndex != currentLine {
                if segment.count > 1 { rides.append(RailRide(line: lines[currentLine], stations: segment)) }
                segment = []
                currentLine = node.lineIndex
            }
            segment.append(station(node))
        }
        if segment.count > 1 { rides.append(RailRide(line: lines[currentLine], stations: segment)) }
        guard !rides.isEmpty else { return nil }

        // Not worth it if walking straight there is about as quick.
        let walkAll = Self.walkMinutes(start.distance(from: end) * Self.detourFactor)
        guard bestTotal < walkAll - 5 else { return nil }

        return RailJourney(
            walkToStationMeters: walkIn,
            rides: rides,
            walkFromStationMeters: bestExitWalk,
            totalMinutes: bestTotal,
            fareTHB: Self.fare(for: rides)
        )
    }

    /// Estimated fare: one fare per paid area (BTS lines share one), by stops ridden.
    static func fare(for rides: [RailRide]) -> Double {
        var total = 0.0
        var index = 0
        while index < rides.count {
            let group = rides[index].line.fareGroup
            let model = rides[index].line.fareModel
            var stops = 0
            while index < rides.count, rides[index].line.fareGroup == group {
                stops += rides[index].stops
                index += 1
            }
            total += min(model.base + model.perStop * Double(max(stops - 1, 0)), model.cap)
        }
        return total.rounded()
    }
}
