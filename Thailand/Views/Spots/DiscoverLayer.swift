import MapKit
import SwiftUI
import UIKit

/// Which Wikipedia places are worth a photo pin: things to see, not districts, roads or schools.
enum DiscoverFilter {
    private static let boring = ["district", "subdistrict", "tambon", "khwaeng", "khet ", "amphoe", "province", "constituency",
                                 "road", "street", "soi ", "school", "university", "college", "hospital", "embassy",
                                 "company", "office", "ministry", "railway station", "bus station", "skytrain station",
                                 "mrt station", "bts station", "interchange", "expressway", "bridge over", "village in"]

    static func isInteresting(_ landmark: Landmark) -> Bool {
        guard landmark.imageURL != nil else { return false }
        let text = (landmark.title + " " + (landmark.shortDescription ?? "")).lowercased()
        return !boring.contains { text.contains($0) }
    }
}

final class DiscoverAnnotation: NSObject, MKAnnotation {
    let landmark: Landmark
    /// A researched must-see (gold star, shown above other discover pins).
    let isTopPick: Bool
    var coordinate: CLLocationCoordinate2D { landmark.coordinate }
    var title: String? { landmark.title }
    init(_ landmark: Landmark, isTopPick: Bool = false) {
        self.landmark = landmark
        self.isTopPick = isTopPick
    }
}

/// Photo pin for a place to discover: slightly smaller, with a sparkle badge, below your own spots.
final class DiscoverAnnotationView: MKAnnotationView {
    static let id = "discover"
    private static let size: CGFloat = 40
    private let photo = UIImageView()
    private let ring = UIView()
    private let badge = UIImageView()
    private let label = UILabel()
    private var loadTask: Task<Void, Never>?

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let s = Self.size
        frame = CGRect(x: 0, y: 0, width: s + 6, height: s + 6)
        collisionMode = .circle
        displayPriority = .defaultLow // your saved spots win when pins overlap

        ring.frame = CGRect(x: 3, y: 3, width: s, height: s)
        ring.layer.cornerRadius = s / 2
        ring.backgroundColor = .white
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.2
        ring.layer.shadowRadius = 3
        ring.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(ring)

        photo.frame = ring.frame.insetBy(dx: 2, dy: 2)
        photo.layer.cornerRadius = photo.frame.width / 2
        photo.clipsToBounds = true
        photo.contentMode = .scaleAspectFill
        photo.backgroundColor = UIColor.secondarySystemFill
        addSubview(photo)

        badge.frame = CGRect(x: s - 10, y: -1, width: 16, height: 16)
        badge.image = UIImage(systemName: "sparkles")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 8, weight: .bold))
        badge.contentMode = .center
        badge.tintColor = .white
        badge.backgroundColor = UIColor(Theme.mango)
        badge.layer.cornerRadius = 8
        badge.layer.borderColor = UIColor.white.cgColor
        badge.layer.borderWidth = 1.5
        badge.clipsToBounds = true
        addSubview(badge)

        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.layer.shadowColor = UIColor.systemBackground.cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        label.frame = CGRect(x: -34, y: s + 6, width: s + 74, height: 13)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        photo.image = nil
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        UIView.animate(withDuration: animated ? 0.2 : 0) {
            self.transform = selected ? CGAffineTransform(scaleX: 1.25, y: 1.25) : .identity
        }
    }

    private func configure() {
        guard let discover = annotation as? DiscoverAnnotation else { return }
        let landmark = discover.landmark
        label.text = landmark.title
        badge.image = UIImage(systemName: discover.isTopPick ? "star.fill" : "sparkles")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 8, weight: .bold))
        badge.backgroundColor = discover.isTopPick ? UIColor(hex: "#E8A317") : UIColor(Theme.mango)
        displayPriority = discover.isTopPick ? MKFeatureDisplayPriority(rawValue: 600) : .defaultLow
        label.textColor = discover.isTopPick ? .label : .secondaryLabel
        accessibilityLabel = "Discover: \(landmark.title)"
        loadTask?.cancel()
        // Placeholder until (or unless) there's a photo: the place's category icon.
        let category = SpotCategory.allCases.first { $0.title == landmark.shortDescription } ?? .explore
        let tint = UIColor(category.color)
        photo.backgroundColor = tint.withAlphaComponent(0.18)
        photo.contentMode = .center
        photo.image = UIImage(systemName: category.systemImage)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        guard let url = landmark.imageURL else { return }
        let id = landmark.id
        loadTask = Task { @MainActor [weak self] in
            guard let image = await ImageCache.image(at: url), !Task.isCancelled, let self,
                  (self.annotation as? DiscoverAnnotation)?.landmark.id == id else { return }
            UIView.transition(with: self.photo, duration: 0.25, options: .transitionCrossDissolve) {
                self.photo.contentMode = .scaleAspectFill
                self.photo.image = image
            }
        }
    }
}

/// Loads discover pins for whatever area is on screen (once zoomed in to city level).
@MainActor
final class DiscoverLoader {
    private var loadedCells: Set<String> = []
    private var known: [Int: Landmark] = [:]
    private var pending: Task<Void, Never>?

    /// Zoomed in enough to show discover pins (about 25 km across or less: a city or closer).
    static func isZoomedIn(_ region: MKCoordinateRegion) -> Bool { min(region.span.latitudeDelta, region.span.longitudeDelta) < 0.2 }

    func regionChanged(_ map: MKMapView, savedSpots: [Spot], completion: @escaping ([Landmark]) -> Void) {
        pending?.cancel()
        let region = map.region
        guard Self.isZoomedIn(region) else { return }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600)) // wait until the map stops moving
            guard !Task.isCancelled else { return }
            // Sample the middle and each quarter of the screen so pins cover the whole view.
            let dLat = region.span.latitudeDelta / 4, dLon = region.span.longitudeDelta / 4
            let points = [(0.0, 0.0), (dLat, dLon), (dLat, -dLon), (-dLat, dLon), (-dLat, -dLon)].map {
                CLLocationCoordinate2D(latitude: region.center.latitude + $0.0, longitude: region.center.longitude + $0.1)
            }
            let radius = Int(min(10_000, max(1_500, min(region.span.latitudeDelta, region.span.longitudeDelta) * 111_000 * 0.45)))
            await withTaskGroup(of: [Landmark].self) { group in
                for p in points {
                    let cell = String(format: "%.2f,%.2f", p.latitude, p.longitude)
                    guard !loadedCells.contains(cell) else { continue }
                    loadedCells.insert(cell)
                    group.addTask { (try? await WikipediaService.landmarks(near: p, radius: radius, limit: 40, remember: false)) ?? [] }
                }
                for await found in group { for l in found where DiscoverFilter.isInteresting(l) { known[l.id] = l } }
            }
            guard !Task.isCancelled else { return }
            // Skip places you've already saved.
            let fresh = known.values.filter { l in
                !savedSpots.contains { spot in
                    guard let c = spot.coordinate else { return false }
                    return AutoPlanner.distance(c, l.coordinate) < 120 && NameMatch.similarity(spot.displayName, l.title) >= 0.4
                }
            }
            completion(Array(fresh))
        }
    }
}
