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
}
