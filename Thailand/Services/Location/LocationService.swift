import Foundation
import CoreLocation

/// When-In-Use location only: one-shot lookups plus foreground updates while a screen needs them.
/// Created on the main thread, so delegate callbacks arrive on the main thread.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var heading: CLHeading?

    private let manager: CLLocationManager
    private var pending: [CheckedContinuation<CLLocation?, Never>] = []
    private var updateRequests = 0

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .fitness
    }

    var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }
    var isAuthorized: Bool { authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One-shot location; nil when denied or unavailable.
    func currentLocation() async -> CLLocation? {
        if isDenied { return nil }
        if let lastLocation, Date().timeIntervalSince(lastLocation.timestamp) < 20 {
            return lastLocation
        }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            if isAuthorized {
                manager.requestLocation()
            } else {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    /// Foreground updates. Balanced with `stopUpdating()`; stops when nobody needs them.
    func startUpdating(withHeading: Bool = false) {
        updateRequests += 1
        requestPermission()
        if isAuthorized {
            manager.startUpdatingLocation()
            if withHeading, CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        }
    }

    func stopUpdating() {
        updateRequests = max(updateRequests - 1, 0)
        if updateRequests == 0 {
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
        }
    }

    // MARK: Place names

    /// Neighborhood and city for a location, in English when available ("Phra Nakhon", "Bangkok").
    func placeName(for location: CLLocation) async -> (area: String, city: String)? {
        guard let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")).first else { return nil }
        let area = placemark.subLocality ?? placemark.thoroughfare ?? placemark.name ?? ""
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? ""
        return (area, city)
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            if !pending.isEmpty { manager.requestLocation() }
            if updateRequests > 0 { manager.startUpdatingLocation() }
        } else if isDenied {
            resumePending(with: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        resumePending(with: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resumePending(with: lastLocation)
    }

    private func resumePending(with location: CLLocation?) {
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume(returning: location) }
    }
}
