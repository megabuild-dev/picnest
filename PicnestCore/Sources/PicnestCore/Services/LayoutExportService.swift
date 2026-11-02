import CoreGraphics
import Foundation
import ImageIO

/// The preview and the PNG or PDF export of a layout. The export never changes a photo of the session:
/// it checks every destination against `ProtectedFiles` before it writes, and writes through
/// `ImageExportRepository` (temp file, then move).
public final class LayoutExportService: Sendable {
    private let thumbnails: ThumbnailService
    private let images: ImageRepository
    private let writer: ImageExportRepository

    public init(thumbnails: ThumbnailService, images: ImageRepository, writer: ImageExportRepository = ImageExportRepository()) {
        self.thumbnails = thumbnails
        self.images = images
        self.writer = writer
    }

    /// The preview of `page` with its longest side near `maxPixel`. It uses the cached thumbnails of the
    /// Review grid. Nil if the bitmap cannot be made.
    public func previewImage(
        of page: LayoutPage, document: LayoutDocument, fileNames: [MediaID: String], maxPixel: Int, source: URL
    ) async -> CGImage? {
        let longest = max(page.size.width, page.size.height)
        let dpi = max(Int((Double(maxPixel) / longest * 72).rounded()), 1)
        let thumbnails = thumbnails
        return await renderer(source: source).image(
            of: page, document: document, fileNames: fileNames, dpi: dpi,
            images: { id, needed in
                let step = ThumbnailService.steps.first { $0 >= needed } ?? ThumbnailService.steps[ThumbnailService.steps.count - 1]
                return await thumbnails.thumbnail(at: source.appending(path: id), maxPixel: step)
            })
    }

    /// `url` for a PDF or 1 page. Else `<stem> 1.png`, `<stem> 2.png`, … in the folder of `url`.
    public static func pageURLs(for url: URL, pageCount: Int, format: LayoutExportFormat) -> [URL] {
        guard format == .png, pageCount > 1 else { return [url] }
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        return (1...pageCount).map {
            folder.appending(path: "\(stem) \($0).\(format.fileExtension)", directoryHint: .notDirectory)
        }
    }

    /// Writes the layout and returns the files. Throws, and writes nothing, when a photo file is gone
    /// (`originalMissing`), a destination is a protected photo (`wouldReplaceOriginal`), or a numbered page
    /// name other than `url` exists (`cannotWrite`). Runs off the caller's actor.
    public func export(
        _ d: LayoutDocument, fileNames: [MediaID: String], source: URL, to url: URL, format: LayoutExportFormat,
        protected: ProtectedFiles
    ) async throws -> [URL] {
        try await export(d, fileNames: fileNames, source: source, to: url, format: format, protected: protected, images: nil)
    }

    /// `images` replaces the photo decoder. Tests use it to see the pixel sizes that the export asks for.
    func export(
        _ d: LayoutDocument, fileNames: [MediaID: String], source: URL, to url: URL, format: LayoutExportFormat,
        protected: ProtectedFiles, images provider: LayoutImageProvider?
    ) async throws -> [URL] {
        let pages = LayoutEngine.pages(for: d)
        let urls = Self.pageURLs(for: url, pageCount: pages.count, format: format)
        try preflight(d, source: source, urls: urls, first: url, protected: protected)
        try Task.checkCancellation()
        let unreadable = Flag()
        let images = provider ?? { [images] id, maxPixel in
            let image = images.downsampled(at: source.appending(path: id), maxPixel: maxPixel)
            if image == nil { unreadable.set() }
            return image
        }
        // A detached task does not inherit the cancellation of the caller, so pass it on.
        let work = Task.detached(priority: .userInitiated) { [self] in
            let renderer = renderer(source: source, unreadable: unreadable)
            let dpi = d.resolution.rawValue
            switch format {
            case .png:
                try await writePNG(pages, d, fileNames, renderer, dpi, urls, images, unreadable)
            case .pdf:
                try await writePDF(pages, d, fileNames, renderer, dpi, url, images, unreadable)
            }
            return urls
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    // MARK: - Private

    private func renderer(source: URL, unreadable: Flag? = nil) -> LayoutRenderer {
        let images = images
        return LayoutRenderer(sizes: { id in
            guard let size = images.pixelSize(for: source.appending(path: id)) else {
                unreadable?.set()
                return nil
            }
            return PixelSize(width: size.width, height: size.height)
        })
    }

    /// All the checks that must pass before the first write.
    private func preflight(_ d: LayoutDocument, source: URL, urls: [URL], first: URL, protected: ProtectedFiles) throws {
        let fm = FileManager.default
        for id in Set(d.photoIDs) where !fm.fileExists(atPath: source.appending(path: id).path) {
            throw PhotoExportError.originalMissing
        }
        for u in urls where protected.refuses(u, original: nil) { throw PhotoExportError.wouldReplaceOriginal }
        for u in urls where u != first && fm.fileExists(atPath: u.path) {
            throw PhotoExportError.cannotWrite("\(u.lastPathComponent) already exists.")
        }
    }

    /// 1 bitmap at a time. A page that fails removes the files this export made.
    private func writePNG(
        _ pages: [LayoutPage], _ d: LayoutDocument, _ fileNames: [MediaID: String], _ renderer: LayoutRenderer,
        _ dpi: Int, _ urls: [URL], _ images: LayoutImageProvider, _ unreadable: Flag
    ) async throws {
        var created: [URL] = []
        do {
            for (page, url) in zip(pages, urls) {
                try Task.checkCancellation()
                guard let bitmap = await renderer.image(of: page, document: d, fileNames: fileNames, dpi: dpi, images: images)
                else { throw PhotoExportError.cannotWrite("The page cannot be drawn.") }
                try Task.checkCancellation()
                // A photo that cannot be read throws here, before a file moves into place.
                if unreadable.isSet { throw PhotoExportError.cannotRead }
                // Only the 1 name that the user confirmed may replace a file. A numbered page never does.
                let replacing = urls.count == 1 && FileManager.default.fileExists(atPath: url.path)
                try await writer.write(
                    bitmap, to: url, format: .png, quality: 1,
                    properties: [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi], replacing: replacing)
                if !replacing { created.append(url) }
            }
        } catch {
            // These files did not exist before this export, so removing them leaves the folder as it was.
            for url in created { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    /// All pages go to 1 temp file, page by page. The media box is the page size in points.
    private func writePDF(
        _ pages: [LayoutPage], _ d: LayoutDocument, _ fileNames: [MediaID: String], _ renderer: LayoutRenderer,
        _ dpi: Int, _ url: URL, _ images: LayoutImageProvider, _ unreadable: Flag
    ) async throws {
        let size = d.pageSize
        try await writer.writeFile(to: url, replacing: FileManager.default.fileExists(atPath: url.path)) { temp in
            var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            guard let consumer = CGDataConsumer(url: temp as CFURL),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { throw PhotoExportError.cannotWrite("The file cannot be created.") }
            for page in pages {
                try Task.checkCancellation()
                ctx.beginPDFPage(nil)
                await renderer.draw(page, document: d, fileNames: fileNames, in: ctx, dpi: dpi, images: images)
                ctx.endPDFPage()
            }
            ctx.closePDF()
            // Thrown here, the temp file is removed and the destination is unchanged.
            if unreadable.isSet { throw PhotoExportError.cannotRead }
        }
    }
}

/// A flag that any thread can set. It records that a photo could not be read.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
