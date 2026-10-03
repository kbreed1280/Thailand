import UIKit
import CoreLocation

/// Hand-offs to other apps: Google Maps (walking), Apple Maps, Grab and Bolt.
/// Each falls back to a web link or the App Store if the app isn't installed.
@MainActor
enum ExternalApps {
    // MARK: Google Maps

    static var hasGoogleMaps: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Walking directions in Google Maps; multiple stops become waypoints.
    static func openGoogleMaps(stops: [CLLocationCoordinate2D], travelMode: String = "walking") {
        guard let destination = stops.last else { return }
        let waypoints = stops.dropLast()
        let format: (CLLocationCoordinate2D) -> String = { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }

        if hasGoogleMaps {
            // The app accepts a destination; extra stops are passed as "+to:" segments in daddr.
            var daddr = waypoints.map(format) + [format(destination)]
            if daddr.count > 1 { daddr = [daddr.joined(separator: "+to:")] }
            var components = URLComponents(string: "comgooglemaps://")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: daddr.first),
                URLQueryItem(name: "directionsmode", value: travelMode)
            ]
            if let url = components?.url {
                UIApplication.shared.open(url)
                return
            }
        }

        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: format(destination)),
            URLQueryItem(name: "travelmode", value: travelMode)
        ]
        if !waypoints.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: waypoints.map(format).joined(separator: "|")))
        }
        components?.queryItems = items
        if let url = components?.url { UIApplication.shared.open(url) }
    }

    // MARK: Apple Maps

    static func openAppleMaps(to coordinate: CLLocationCoordinate2D, name: String, walking: Bool = true) {
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [
            URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: name)
        ]
        if walking { items.append(URLQueryItem(name: "dirflg", value: "w")) }
        components?.queryItems = items
        if let url = components?.url { UIApplication.shared.open(url) }
    }

    static func showInAppleMaps(_ coordinate: CLLocationCoordinate2D, name: String) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: name)
        ]
        if let url = components?.url { UIApplication.shared.open(url) }
    }

    // MARK: Phone & web

    static func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") { UIApplication.shared.open(url) }
    }

    // MARK: Ride hailing

    enum RideApp: String, CaseIterable, Identifiable {
        case grab = "Grab"
        case bolt = "Bolt"

        var id: String { rawValue }

        var scheme: String { self == .grab ? "grab://" : "bolt://" }

        var appStoreURL: URL? {
            URL(string: self == .grab ? "https://apps.apple.com/app/id647268330" : "https://apps.apple.com/app/id675033630")
        }

        var colorHex: String { self == .grab ? "#00B14F" : "#34D186" }
    }

    /// Copies the destination (so it can be pasted into the app's search) and opens the app,
    /// or its App Store page when it isn't installed.
    static func openRide(_ app: RideApp, destinationName: String, address: String) {
        let text = [destinationName, address].filter { !$0.isEmpty }.joined(separator: ", ")
        UIPasteboard.general.string = text
        guard let url = URL(string: app.scheme) else { return }
        UIApplication.shared.open(url) { opened in
            if !opened, let store = app.appStoreURL {
                UIApplication.shared.open(store)
            }
        }
    }
}
