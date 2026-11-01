import CoreGraphics
import CoreImage
import Foundation

/// The Core Image pipeline of the photo editor, and (task 4.4) the export of an edited copy.
public final class PhotoEditService: Sendable {
    /// The longest side of the preview, in pixels.
    public static let previewMaxPixel = 1600

    private let thumbnails: ThumbnailService
    private let images: ImageRepository
    private let context: CIContext

    public init(thumbnails: ThumbnailService, images: ImageRepository, context: CIContext = CIContext()) {
        self.thumbnails = thumbnails
        self.images = images
        self.context = context
    }

    /// The upright preview of the photo at `url`. It shares the cache of the thumbnail service.
    public func preview(at url: URL) async -> CGImage? {
        await thumbnails.thumbnail(at: url, maxPixel: Self.previewMaxPixel)
    }

    // MARK: - Pure geometry

    /// The slider values as filter values. This is the 1 place that maps a slider to a filter.
    public static func filterValues(for e: PhotoEdit)
        -> (ev: Double, contrast: Double, saturation: Double, targetKelvin: Double)
    {
        let exposure = Double(e[.exposure]) / 100
        let contrast = Double(e[.contrast]) / 100
        let saturation = Double(e[.saturation]) / 100
        let warmth = Double(e[.warmth]) / 100
        return (
            ev: 2 * exposure,
            contrast: 1 + 0.25 * contrast,
            saturation: 1 + saturation,
            targetKelvin: 6500 + 2000 * Self.warmthDirection * warmth)
    }

    /// Which way the target temperature moves for a warmer picture.
    private static let warmthDirection = -1.0

    /// The size of the frame after the quarter turns. Straighten keeps the size.
    static func frameSize(of e: PhotoEdit, source: PixelSize) -> PixelSize {
        e.quarterTurns % 2 == 1 ? PixelSize(width: source.height, height: source.width) : source
    }

    /// The crop in whole pixels of the frame, top left origin. At least 1 × 1, always inside the frame.
    static func cropPixels(_ crop: NormalizedRect, in frame: PixelSize) -> (x: Int, y: Int, width: Int, height: Int) {
        let w = Double(frame.width), h = Double(frame.height)
        let x0 = min(max((crop.x * w).rounded(), 0), w - 1)
        let y0 = min(max((crop.y * h).rounded(), 0), h - 1)
        let x1 = min(max(((crop.x + crop.width) * w).rounded(), x0 + 1), w)
        let y1 = min(max(((crop.y + crop.height) * h).rounded(), y0 + 1), h)
        return (Int(x0), Int(y0), Int(x1 - x0), Int(y1 - y0))
    }

    public static func outputSize(of e: PhotoEdit, source: PixelSize) -> PixelSize {
        let frame = frameSize(of: e, source: source)
        let c = cropPixels(e.crop, in: frame)
        return PixelSize(width: c.width, height: c.height)
    }

    // MARK: - Pipeline

    /// The edited image. With `cropping` false, the whole frame after the turns, flips, and straighten.
    /// The result keeps the color space of `image` (sRGB if it has no RGB space).
    public func apply(_ e: PhotoEdit, to image: CGImage, cropping: Bool = true) -> CGImage? {
        let source = PixelSize(width: image.width, height: image.height)
        let frame = Self.frameSize(of: e, source: source)
        var ci = CIImage(cgImage: image)

        // Quarter turns clockwise, then the flips, in the frame the user sees.
        if e.quarterTurns != 0 {
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(e.quarterTurns) * .pi / 2))
        }
        if e.flipHorizontal { ci = ci.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
        if e.flipVertical { ci = ci.transformed(by: CGAffineTransform(scaleX: 1, y: -1)) }
        let frameRect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.minX, y: -ci.extent.minY))

        // Straighten about the center, at the smallest scale that covers the frame. Positive is clockwise.
        if e.straighten != 0 {
            let scale = CropGeometry.straightenScale(
                degrees: e.straighten, width: Double(frame.width), height: Double(frame.height))
            let center = CGPoint(x: frameRect.midX, y: frameRect.midY)
            // Each call applies its step before the steps already in the matrix.
            let t = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: -e.straighten * .pi / 180)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
            ci = ci.clampedToExtent().transformed(by: t).cropped(to: frameRect)
        }

        ci = adjusted(ci, for: e)

        var rect = frameRect
        if cropping {
            let c = Self.cropPixels(e.crop, in: frame)
            // Core Image has its origin at the bottom left.
            rect = CGRect(x: c.x, y: frame.height - c.y - c.height, width: c.width, height: c.height)
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(ci, from: rect, format: .RGBA8, colorSpace: space)
    }

    private func adjusted(_ input: CIImage, for e: PhotoEdit) -> CIImage {
        let v = Self.filterValues(for: e)
        var ci = input
        if e[.exposure] != 0 {
            ci = ci.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: v.ev])
        }
        if e[.contrast] != 0 || e[.saturation] != 0 {
            ci = ci.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: v.contrast, kCIInputSaturationKey: v.saturation,
            ])
        }
        if e[.warmth] != 0 {
            ci = ci.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: v.targetKelvin, y: 0),
            ])
        }
        return ci
    }
}
