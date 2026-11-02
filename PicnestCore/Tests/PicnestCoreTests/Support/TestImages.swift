import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    enum Failure: Error { case encode }

    static func writeJPEG(
        to url: URL, color: (r: UInt8, g: UInt8, b: UInt8), exifDate: Date? = nil, size: Int = 32
    ) throws {
        try write(to: url, type: UTType.jpeg, color: color, exifDate: exifDate, size: size)
    }

    static func writeHEIC(
        to url: URL, color: (r: UInt8, g: UInt8, b: UInt8), exifDate: Date? = nil, size: Int = 32
    ) throws {
        try write(to: url, type: UTType.heic, color: color, exifDate: exifDate, size: size)
    }

    private static func write(
        to url: URL, type: UTType, color: (r: UInt8, g: UInt8, b: UInt8), exifDate: Date?, size: Int
    ) throws {
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure.encode }
        ctx.setFillColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                         blue: CGFloat(color.b) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw Failure.encode }
        var props: [CFString: Any] = [:]
        if let exifDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: f.string(from: exifDate)]
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.encode }
    }

    // MARK: - Quadrants

    typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

    /// Writes an image of `width` × `height` stored pixels. After `orientation` is applied, the top left is
    /// red, the top right green, the bottom left blue, and the bottom right white. The channel values are
    /// written in `colorSpace`, so a read in the same space gives them back.
    static func writeQuadrants(
        to url: URL, type: UTType, width: Int, height: Int, orientation: Int = 1,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
        extra: [CFString: Any] = [:], options: [CFString: Any] = [:]
    ) throws {
        let image = try quadrantImage(width: width, height: height, orientation: orientation, colorSpace: colorSpace)
        var props: [CFString: Any] = extra
        if orientation != 1 { props[kCGImagePropertyOrientation] = orientation }
        try save(image, to: url, type: type, properties: props, options: options)
    }

    static func save(
        _ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any] = [:], options: [CFString: Any] = [:]
    ) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, options as CFDictionary)
        else { throw Failure.encode }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.encode }
    }

    static func quadrantImage(
        width: Int, height: Int, orientation: Int = 1,
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) throws -> CGImage {
        let shown = orientation >= 5 ? (w: height, h: width) : (w: width, h: height)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (sx, sy): (Int, Int)
                switch orientation {
                case 2: (sx, sy) = (shown.w - 1 - x, y)
                case 3: (sx, sy) = (shown.w - 1 - x, shown.h - 1 - y)
                case 4: (sx, sy) = (x, shown.h - 1 - y)
                case 5: (sx, sy) = (y, x)
                case 6: (sx, sy) = (height - 1 - y, x)
                case 7: (sx, sy) = (height - 1 - y, width - 1 - x)
                case 8: (sx, sy) = (y, width - 1 - x)
                default: (sx, sy) = (x, y)
                }
                let left = sx < shown.w / 2, top = sy < shown.h / 2
                let c: RGB = top ? (left ? (255, 0, 0) : (0, 255, 0)) : (left ? (0, 0, 255) : (255, 255, 255))
                let i = (y * width + x) * 4
                bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b
            }
        }
        return try image(rgba: bytes, width: width, height: height, colorSpace: colorSpace)
    }

    /// A 1-colour image, and an image from raw RGBA bytes (row 0 is the top).
    static func solid(_ c: RGB, width: Int = 8, height: Int = 8, alpha: UInt8 = 255) throws -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            // Premultiplied.
            bytes[i * 4] = UInt8(Int(c.r) * Int(alpha) / 255)
            bytes[i * 4 + 1] = UInt8(Int(c.g) * Int(alpha) / 255)
            bytes[i * 4 + 2] = UInt8(Int(c.b) * Int(alpha) / 255)
            bytes[i * 4 + 3] = alpha
        }
        return try image(rgba: bytes, width: width, height: height, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                         premultiplied: true)
    }

    private static func image(
        rgba: [UInt8], width: Int, height: Int, colorSpace: CGColorSpace, premultiplied: Bool = false
    ) throws -> CGImage {
        let info = premultiplied ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw Failure.encode }
        return image
    }

    /// The pixel at `point` (origin top left), read in sRGB.
    static func color(at point: (x: Int, y: Int), in image: CGImage) -> RGB {
        let p = rgba(at: point, in: image)
        return (p.r, p.g, p.b)
    }

    static func rgba(at point: (x: Int, y: Int), in image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setBlendMode(.copy)
        // Draw so that the wanted pixel lands on the 1 × 1 context.
        ctx.draw(image, in: CGRect(x: -point.x, y: point.y - image.height + 1, width: image.width, height: image.height))
        return (px[0], px[1], px[2], px[3])
    }
}
