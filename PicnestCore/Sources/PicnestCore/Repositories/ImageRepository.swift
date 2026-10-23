import CoreGraphics
import Foundation
import ImageIO

/// Decodes thumbnails off the caller's actor and keeps them in a memory cache of at most 200 MB.
/// `NSCache` is thread-safe, and this class has no other mutable state, so `@unchecked Sendable` is safe.
public final class ImageRepository: @unchecked Sendable {
    private let cache: NSCache<NSString, CGImage>

    public init(totalCostLimit: Int = 200 * 1024 * 1024) {
        cache = NSCache()
        cache.totalCostLimit = totalCostLimit
    }

    public func thumbnail(for url: URL, maxPixel: Int) async -> CGImage? {
        let key = "\(url.path)|\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .utility) { Self.decode(url, maxPixel: maxPixel) }.value
        if let image { cache.setObject(image, forKey: key, cost: image.width * image.height * 4) }
        return image
    }

    /// The pixel size of the image at `url`, read from the image properties without a decode.
    /// Width and height are as shown (an EXIF rotation of 90° swaps them). Nil when it cannot be read.
    public func pixelSize(for url: URL) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
    }

    private static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
