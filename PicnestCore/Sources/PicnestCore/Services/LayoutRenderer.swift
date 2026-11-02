import CoreGraphics
import CoreText
import Foundation

/// Gives the image of a photo with its longest side at most the second value, or nil if it cannot be read.
public typealias LayoutImageProvider = @Sendable (MediaID, Int) async -> CGImage?

/// Draws a layout page. It asks an image provider for 1 photo at a time and lets go of it before the next.
/// The colors are fixed sRGB values and the font is the system font, so the page does not follow Light or Dark.
public struct LayoutRenderer: Sendable {
    public static let captionFontSize: CGFloat = 9
    public static let titleFontSize: CGFloat = 14
    public static let noteFontSize: CGFloat = 10

    private let sizes: @Sendable (MediaID) async -> PixelSize?

    /// `sizes` gives the pixel size of a photo, as shown (upright).
    public init(sizes: @escaping @Sendable (MediaID) async -> PixelSize?) {
        self.sizes = sizes
    }

    /// Draws `page` in `ctx`. The context is in points with the origin at the bottom left (a PDF page, or a
    /// bitmap scaled by the caller). `dpi` only sets the pixel size that each photo needs.
    public func draw(
        _ page: LayoutPage, document d: LayoutDocument, fileNames: [MediaID: String], in ctx: CGContext, dpi: Int,
        images: LayoutImageProvider
    ) async {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.saveGState()
        Self.useTopLeftOrigin(ctx, height: page.size.height)
        let bg = d.background.rgb
        ctx.setFillColor(CGColor(colorSpace: srgb, components: [bg.r, bg.g, bg.b, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: page.size.width, height: page.size.height))
        ctx.interpolationQuality = .high

        for cell in page.cells {
            if Task.isCancelled { break }
            guard let id = cell.mediaID, let size = await sizes(id), size.width > 0, size.height > 0 else { continue }
            let needed = LayoutEngine.neededPixels(for: cell.imageArea, source: size, fit: cell.fit, dpi: dpi)
            guard needed > 0, let image = await images(id, needed) else { continue }
            let rect = LayoutEngine.imageRect(source: size, in: cell.imageArea, fit: cell.fit)
            ctx.saveGState()
            ctx.clip(to: Self.cgRect(cell.imageArea))
            // The context is flipped, so flip once more around the image to draw it upright.
            ctx.translateBy(x: rect.x, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            ctx.restoreGState()
        }

        let text = d.background.textRGB
        let color = CGColor(colorSpace: srgb, components: [text.r, text.g, text.b, 1])!
        for cell in page.cells {
            guard let caption = cell.caption, let id = cell.mediaID else { continue }
            let name = fileNames[id] ?? (id as NSString).lastPathComponent
            Self.drawLine(name, size: Self.captionFontSize, color: color, in: caption, centered: true, ctx: ctx)
        }
        if let footer = page.footer {
            let half = footer.height / 2
            let titleRect = LayoutRect(x: footer.x, y: footer.y, width: footer.width, height: half)
            let noteRect = LayoutRect(x: footer.x, y: footer.y + half, width: footer.width, height: footer.height - half)
            Self.drawLine(d.title, size: Self.titleFontSize, color: color, in: titleRect, centered: false, ctx: ctx)
            Self.drawLine(d.note, size: Self.noteFontSize, color: color, in: noteRect, centered: false, ctx: ctx)
        }
        ctx.restoreGState()
    }

    /// A bitmap of the page in sRGB, 8 bits, `LayoutEngine.pixelSize` pixels. For the preview and the PNG export.
    public func image(
        of page: LayoutPage, document d: LayoutDocument, fileNames: [MediaID: String], dpi: Int,
        images: LayoutImageProvider
    ) async -> CGImage? {
        let size = LayoutEngine.pixelSize(of: page.size, dpi: dpi)
        guard size.width > 0, size.height > 0, let ctx = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Points to pixels. The page size in pixels is rounded, so scale each axis to fill the bitmap.
        ctx.scaleBy(x: Double(size.width) / page.size.width, y: Double(size.height) / page.size.height)
        await draw(page, document: d, fileNames: fileNames, in: ctx, dpi: dpi, images: images)
        return ctx.makeImage()
    }

    // MARK: - Private

    /// The 1 place that flips the context: afterwards the origin is the top left and y grows down.
    private static func useTopLeftOrigin(_ ctx: CGContext, height: Double) {
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
    }

    private static func cgRect(_ r: LayoutRect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }

    /// 1 line of text in `rect`, centered vertically, cut with an ellipsis at the end when it is too wide.
    private static func drawLine(
        _ string: String, size: CGFloat, color: CGColor, in rect: LayoutRect, centered: Bool, ctx: CGContext
    ) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let font = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, text.replacingOccurrences(of: "\n", with: " ") as CFString, attributes as CFDictionary)!)
        var drawn = line
        if CTLineGetTypographicBounds(line, nil, nil, nil) > rect.width {
            let ellipsis = CTLineCreateWithAttributedString(
                CFAttributedStringCreate(nil, "\u{2026}" as CFString, attributes as CFDictionary)!)
            drawn = CTLineCreateTruncatedLine(line, rect.width, .end, ellipsis) ?? line
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(drawn, &ascent, &descent, nil)
        let x = rect.x + (centered ? max((rect.width - width) / 2, 0) : 0)
        let baseline = rect.y + (rect.height + ascent - descent) / 2
        ctx.saveGState()
        // The context is flipped, so the text matrix flips the glyphs back.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(drawn, ctx)
        ctx.restoreGState()
    }
}
