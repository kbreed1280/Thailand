import UIKit
import ImageIO

enum ImageProcessing {
    /// Downsamples without decoding the full image into memory.
    static func thumbnail(from data: Data, maxPixel: CGFloat = 500) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75)
    }

    /// Photos synced through iCloud should stay reasonably small: cap the long edge at 2048 px.
    static func preparedForStorage(_ data: Data) -> Data {
        thumbnail(from: data, maxPixel: 2048) ?? data
    }
}
