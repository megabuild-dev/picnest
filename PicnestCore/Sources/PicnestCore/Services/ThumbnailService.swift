import CoreGraphics
import Foundation

/// Thumbnails of the photos in a source folder, for the Review grid (spec 3.3).
/// Wraps `ImageRepository`, so view models never call the repository. The app makes 1 instance,
/// so all screens share 1 memory cache.
public final class ThumbnailService: Sendable {
    /// The decode sizes. Tiles of near widths ask for the same size, so the cache is reused.
    public static let steps = [200, 400, 800, 1600]

    private let images: ImageRepository

    public init(images: ImageRepository) {
        self.images = images
    }

    /// The thumbnail of `media` (at `source` + its relative path), or nil if it cannot be decoded.
    /// Decoding runs off the caller's actor.
    public func thumbnail(for media: MediaFile, source: URL, maxPixel: Int) async -> CGImage? {
        await images.thumbnail(for: source.appending(path: media.relativePath), maxPixel: maxPixel)
    }

    /// 2 × the tile width in points (for Retina screens), rounded up to the next step.
    /// Widths above the last step use the last step.
    public static func maxPixel(forTileWidth width: Double) -> Int {
        let wanted = Int((2 * width).rounded(.up))
        return steps.first { $0 >= wanted } ?? steps[steps.count - 1]
    }
}
