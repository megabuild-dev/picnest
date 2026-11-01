import CoreGraphics
import Foundation
import ImageIO

/// Writes an image file. It writes a temp file in the folder of the destination, then moves it into place,
/// so a failed export leaves no file at the destination and no temp file.
public struct ImageExportRepository: Sendable {
    private let fileOps: any FileOps

    public init(fileOps: any FileOps = LocalFileOps()) {
        self.fileOps = fileOps
    }

    /// With `replacing` false, a file at `url` makes this throw, and nothing changes.
    /// With `replacing` true, the file at `url` is replaced in 1 step.
    public func write(
        _ image: CGImage, to url: URL, format: ExportFormat, quality: Double,
        properties: [CFString: Any], replacing: Bool
    ) throws {
        let temp = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try encode(image, to: temp, format: format, quality: quality, properties: properties)
            try Task.checkCancellation()
            if replacing {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            } else {
                try fileOps.move(temp, url)
            }
        } catch {
            try? fileOps.remove(temp)
            if error is CancellationError || error is PhotoExportError { throw error }
            throw PhotoExportError.cannotWrite(error.localizedDescription)
        }
    }

    private func encode(
        _ image: CGImage, to url: URL, format: ExportFormat, quality: Double, properties: [CFString: Any]
    ) throws {
        let flat = format == .png ? image : Self.onWhite(image)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil)
        else { throw PhotoExportError.cannotWrite("The file cannot be created.") }
        var props = properties
        if format != .png { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, flat, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoExportError.cannotWrite("The image cannot be encoded.")
        }
    }

    /// JPEG and HEIC have no alpha: draw the image on white.
    private static func onWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }
}
