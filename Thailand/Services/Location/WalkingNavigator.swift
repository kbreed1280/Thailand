import Foundation
import MapKit

/// Live walking guidance to one destination while the app is open:
/// remaining distance and time, the current step, off-route re-routing and arrival.
@MainActor
final class WalkingNavigator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case routing
        case navigating
        case arrived
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var route: MKRoute?
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var remainingMeters: CLLocationDistance = 0
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var metersToNextStep: CLLocationDistance = 0
    @Published private(set) var isOffRoute = false

    let destination: CLLocationCoordinate2D
    let destinationName: String

    private var points: [MKMapPoint] = []
    private var cumulative: [CLLocationDistance] = []
    private var stepEnds: [CLLocationDistance] = []
    private var lastRerouteAt = Date.distantPast
    private var lastIndex = 0

    static let arrivalRadius: CLLocationDistance = 25
    static let offRouteDistance: CLLocationDistance = 60

    init(destination: CLLocationCoordinate2D, destinationName: String) {
        self.destination = destination
        self.destinationName = destinationName
    }

    var steps: [MKRoute.Step] {
        (route?.steps ?? []).filter { !$0.instructions.isEmpty }
    }

    var currentInstruction: String {
        guard phase == .navigating else { return "" }
        let visible = steps
        guard !visible.isEmpty else { return "Head to \(destinationName)" }
        let index = min(currentStepIndex, visible.count - 1)
        return visible[index].instructions
    }

    var arrivalTime: Date { Date().addingTimeInterval(remainingSeconds) }

    // MARK: Routing

    func calculate(from location: CLLocation) async {
        phase = .routing
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        do {
            guard let best = try await MKDirections(request: request).calculate().routes.first else {
                phase = .failed("No walking route found.")
                return
            }
            apply(best)
            phase = .navigating
            update(with: location)
        } catch {
            phase = .failed(NetworkMonitor.shared.isOnline
                ? "Couldn't get walking directions here. Try Google Maps."
                : "Walking directions need internet. Google Maps works offline if you downloaded the area.")
        }
    }

    private func apply(_ newRoute: MKRoute) {
        route = newRoute
        let polyline = newRoute.polyline
        points = (0..<polyline.pointCount).map { polyline.points()[$0] }
        routeCoordinates = points.map(\.coordinate)
        cumulative = []
        var total: CLLocationDistance = 0
        for (index, point) in points.enumerated() {
            if index > 0 { total += points[index - 1].distance(to: point) }
            cumulative.append(total)
        }
        var running: CLLocationDistance = 0
        stepEnds = newRoute.steps.filter { !$0.instructions.isEmpty }.map { step in
            running += step.distance
            return running
        }
        lastIndex = 0
        currentStepIndex = 0
        isOffRoute = false
    }

    // MARK: Progress

    func update(with location: CLLocation) {
        let toDestination = location.distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        if toDestination <= Self.arrivalRadius, phase == .navigating {
            phase = .arrived
            remainingMeters = 0
            remainingSeconds = 0
            return
        }
        guard phase == .navigating, let route, !points.isEmpty else { return }

        let here = MKMapPoint(location.coordinate)
        var nearestIndex = lastIndex
        var nearestDistance = CLLocationDistance.greatestFiniteMagnitude
        for index in points.indices {
            let distance = here.distance(to: points[index])
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        lastIndex = nearestIndex

        let total = cumulative.last ?? route.distance
        let traveled = cumulative[nearestIndex]
        remainingMeters = max(total - traveled, 0) + min(nearestDistance, Self.offRouteDistance)
        let speed = route.expectedTravelTime > 0 ? route.distance / route.expectedTravelTime : 1.3
        remainingSeconds = remainingMeters / max(speed, 0.5)

        if let next = stepEnds.firstIndex(where: { $0 > traveled + 5 }) {
            currentStepIndex = next
            metersToNextStep = max(stepEnds[next] - traveled, 0)
        }

        isOffRoute = nearestDistance > Self.offRouteDistance
        if isOffRoute, Date().timeIntervalSince(lastRerouteAt) > 20 {
            lastRerouteAt = .now
            Task { await calculate(from: location) }
        }
    }
}
