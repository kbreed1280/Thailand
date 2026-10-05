import MapKit
import SwiftUI
import UIKit

/// The best picture for a spot: the post it came from (when that post is about this one place),
/// a Wikipedia photo, or the place's own website photo (hotels, restaurants).
enum SpotPhoto {
    @MainActor
    static func url(for spot: Spot) async -> URL? {
        if let post = spot.sources.first(where: { ($0.thumbnailURL ?? "").isEmpty == false && $0.spots.count == 1 })?
            .thumbnailURL.flatMap(URL.init(string:)) {
            return post
        }
        guard let c = spot.coordinate else { return nil }
        let website = (spot.website ?? "").isEmpty ? nil : URL(string: spot.website!)
        return await PlacePhotos.shared.photo(name: spot.displayName, coordinate: c, website: website)
    }
}

/// Small in-memory image cache for map pins and cards.
enum ImageCache {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(at url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }
        // Pins are tiny: keep a small copy.
        let small = image.preparingThumbnail(of: CGSize(width: 160, height: 160 * image.size.height / max(image.size.width, 1))) ?? image
        cache.setObject(small, forKey: url as NSURL)
        return small
    }
}

/// Round photo pin with a category badge and the spot's name underneath (Plotline style).
/// Falls back to the category icon until (or unless) a photo is found.
final class SpotPhotoAnnotationView: MKAnnotationView {
    static let id = "spotPhoto"
    private static let size: CGFloat = 46

    private let photo = UIImageView()
    private let ring = UIView()
    private let badge = UIImageView()
    private let badgeBack = UIView()
    private let label = UILabel()
    private var loadTask: Task<Void, Never>?

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let s = Self.size
        frame = CGRect(x: 0, y: 0, width: s + 8, height: s + 8)
        centerOffset = .zero
        collisionMode = .circle
        displayPriority = .defaultHigh
        clusteringIdentifier = "spots"

        ring.frame = CGRect(x: 4, y: 4, width: s, height: s)
        ring.layer.cornerRadius = s / 2
        ring.backgroundColor = .white
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.25
        ring.layer.shadowRadius = 4
        ring.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(ring)

        photo.frame = ring.frame.insetBy(dx: 2.5, dy: 2.5)
        photo.layer.cornerRadius = photo.frame.width / 2
        photo.clipsToBounds = true
        photo.contentMode = .scaleAspectFill
        addSubview(photo)

        badgeBack.frame = CGRect(x: s - 12, y: s - 12, width: 20, height: 20)
        badgeBack.layer.cornerRadius = 10
        badgeBack.layer.borderColor = UIColor.white.cgColor
        badgeBack.layer.borderWidth = 2
        addSubview(badgeBack)
        badge.frame = badgeBack.frame.insetBy(dx: 4.5, dy: 4.5)
        badge.contentMode = .scaleAspectFit
        badge.tintColor = .white
        addSubview(badge)

        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.textColor = .label
        label.layer.shadowColor = UIColor.systemBackground.cgColor
        label.layer.shadowOpacity = 1
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        label.frame = CGRect(x: -36, y: s + 8, width: s + 80, height: 14)
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
            self.transform = selected ? CGAffineTransform(scaleX: 1.2, y: 1.2) : .identity
        }
    }

    private func configure() {
        guard let spot = (annotation as? SpotAnnotation)?.spot else { return }
        clusteringIdentifier = "spots"
        let color = UIColor(spot.category.color)
        badgeBack.backgroundColor = color
        badge.image = UIImage(systemName: spot.isVisited ? "checkmark" : spot.category.systemImage)?
            .withConfiguration(UIImage.SymbolConfiguration(weight: .bold))
        label.text = spot.displayName
        alpha = spot.isDraft ? 0.6 : 1
        accessibilityLabel = "\(spot.displayName), \(spot.category.title)"

        // Placeholder: the category icon on a soft tint.
        photo.backgroundColor = color.withAlphaComponent(0.18)
        photo.image = UIImage(systemName: spot.category.systemImage)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            .withTintColor(color, renderingMode: .alwaysOriginal)
        photo.contentMode = .center

        loadTask?.cancel()
        let id = spot.objectID
        loadTask = Task { @MainActor [weak self] in
            guard let url = await SpotPhoto.url(for: spot), let image = await ImageCache.image(at: url),
                  !Task.isCancelled, let self, (self.annotation as? SpotAnnotation)?.spot.objectID == id else { return }
            UIView.transition(with: self.photo, duration: 0.25, options: .transitionCrossDissolve) {
                self.photo.contentMode = .scaleAspectFill
                self.photo.image = image
            }
        }
    }
}
