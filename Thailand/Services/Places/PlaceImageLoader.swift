import UIKit
import MapKit

/// A preview image for a place: a Look Around snapshot when Apple has street-level imagery there,
/// otherwise a map snapshot. Results are cached in memory for the session.
@MainActor
enum PlaceImageLoader {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for coordinate: CLLocationCoordinate2D, size: CGSize = CGSize(width: 640, height: 360)) async -> UIImage? {
        let key = String(format: "%.5f,%.5f,%.0f", coordinate.latitude, coordinate.longitude, size.width) as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image: UIImage?
        if let lookAround = await lookAroundImage(at: coordinate, size: size) {
            image = lookAround
        } else {
            image = await mapImage(at: coordinate, size: size)
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    static func lookAroundScene(at coordinate: CLLocationCoordinate2D) async -> MKLookAroundScene? {
        try? await MKLookAroundSceneRequest(coordinate: coordinate).scene
    }

    private static func lookAroundImage(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        guard let scene = await lookAroundScene(at: coordinate) else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        return try? await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
    }

    private static func mapImage(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        options.size = size
        options.pointOfInterestFilter = .includingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        // Draw a pin in the middle.
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let point = snapshot.point(for: coordinate)
            let pin = UIImage(systemName: "mappin.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 34, weight: .bold))
                .withTintColor(UIColor(hex: "#F4821C"), renderingMode: .alwaysOriginal)
            pin?.draw(at: CGPoint(x: point.x - 17, y: point.y - 17))
        }
    }
}
