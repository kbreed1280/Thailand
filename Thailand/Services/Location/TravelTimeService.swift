import Foundation
import MapKit

struct TravelLeg: Equatable {
    var seconds: TimeInterval
    var meters: CLLocationDistance
}

/// Travel time and distance between two stops (MKDirections ETA), cached in memory by
/// (from, to, mode, hour) so scrolling the itinerary doesn't re-request.
@MainActor
final class TravelTimeService {
    static let shared = TravelTimeService()

    private var cache: [String: TravelLeg] = [:]
    private var failures: Set<String> = []
    private var routeCache: [String: MKRoute] = [:]

    private func key(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D, _ mode: TravelMode, _ date: Date?) -> String {
        let hour = date.map { Calendar.current.component(.hour, from: $0) } ?? -1
        return String(format: "%.5f,%.5f>%.5f,%.5f|%@|%d", from.latitude, from.longitude, to.latitude, to.longitude, mode.rawValue, hour)
    }

    func cachedLeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: TravelMode, at date: Date?) -> TravelLeg? {
        cache[key(from, to, mode, date)]
    }

    /// Returns nil when there's no route or no network.
    func leg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: TravelMode, at date: Date?) async -> TravelLeg? {
        let cacheKey = key(from, to, mode, date)
        if let cached = cache[cacheKey] { return cached }
        if failures.contains(cacheKey) || !NetworkMonitor.shared.isOnline { return nil }

        let request = makeRequest(from: from, to: to, mode: mode, at: date)
        do {
            let response = try await MKDirections(request: request).calculateETA()
            let leg = TravelLeg(seconds: response.expectedTravelTime, meters: response.distance)
            cache[cacheKey] = leg
            return leg
        } catch {
            // Transit ETAs are often unavailable in Thailand; estimate from the walking route instead.
            if mode == .transit, let walking = await leg(from: from, to: to, mode: .walking, at: date) {
                let estimate = TravelLeg(seconds: walking.seconds * 0.5, meters: walking.meters)
                cache[cacheKey] = estimate
                return estimate
            }
            failures.insert(cacheKey)
            return nil
        }
    }

    /// Full route (with polyline) for the day route map.
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: TravelMode) async -> MKRoute? {
        let cacheKey = key(from, to, mode, nil) + "|route"
        if let cached = routeCache[cacheKey] { return cached }
        guard NetworkMonitor.shared.isOnline else { return nil }
        let request = makeRequest(from: from, to: to, mode: mode == .transit ? .walking : mode, at: nil)
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        routeCache[cacheKey] = route
        return route
    }

    private func makeRequest(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: TravelMode, at date: Date?) -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        switch mode {
        case .walking: request.transportType = .walking
        case .transit: request.transportType = .transit
        case .taxi: request.transportType = .automobile
        }
        if let date, date > .now { request.departureDate = date }
        return request
    }
}
