import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PicnestCore

/// Records what the export asks for.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func add(_ maxPixel: Int) { lock.withLock { values.append(maxPixel) } }
    var calls: [Int] { lock.withLock { values } }
}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<[URL], Error>?
    func set(_ t: Task<[URL], Error>) { lock.withLock { task = t } }
    func cancel() { lock.withLock { task?.cancel() } }
}

struct LayoutExportTests {
    let images = ImageRepository()

    private func service(writer: ImageExportRepository = ImageExportRepository()) -> LayoutExportService {
        LayoutExportService(thumbnails: ThumbnailService(images: images), images: images, writer: writer)
    }

    /// A source folder with `count` photos named `IMG_0001.png` …, and an empty `Out` folder.
    private func fixture(photos count: Int = 2) throws -> (dir: TempDir, source: URL, out: URL, ids: [MediaID]) {
        let dir = try TempDir()
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        let out = dir.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let ids = (1...max(count, 1)).prefix(count).map { String(format: "img_%04d.png", $0) }
        for id in ids {
            try TestImages.writeQuadrants(to: source.appending(path: id), type: .png, width: 80, height: 60)
        }
        return (dir, source, out, ids)
    }

    private func protected(_ source: URL, _ ids: [MediaID]) -> ProtectedFiles {
        ProtectedFiles(source: source, mediaIDs: Set(ids), otherPaths: [])
    }

    private func fingerprints(_ folder: URL, _ ids: [MediaID]) throws -> [FileFingerprint] {
        try ids.map { try FileFingerprint(of: folder.appending(path: $0)) }
    }

    private func names(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private func pngSize(_ url: URL) throws -> (Int, Int) {
        let s = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let p = try #require(CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any])
        return ((p[kCGImagePropertyPixelWidth] as? Int) ?? 0, (p[kCGImagePropertyPixelHeight] as? Int) ?? 0)
    }

    @Test func a4LandscapePNGIs3508By2480() async throws {
        let f = try fixture()
        let before = try f.ids.map { try FileFingerprint(of: f.source.appending(path: $0)) }
        let d = LayoutDocument(photoIDs: f.ids, resolution: .high)
        let url = f.out.appending(path: "Sheet.png")
        let written = try await service().export(
            d, fileNames: [:], source: f.source, to: url, format: .png, protected: protected(f.source, f.ids))
        #expect(written == [url])
        let size = try pngSize(url)
        #expect(size.0 == 3508 && size.1 == 2480)
        #expect(try f.ids.map { try FileFingerprint(of: f.source.appending(path: $0)) } == before)
        #expect(names(f.out) == ["Sheet.png"])
    }

    @Test func a4LandscapePDFMediaBoxIsExact() async throws {
        let f = try fixture()
        let before = try fingerprints(f.source, f.ids)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        let url = f.out.appending(path: "Sheet.pdf")
        _ = try await service().export(
            d, fileNames: [:], source: f.source, to: url, format: .pdf, protected: protected(f.source, f.ids))
        let pdf = try #require(CGPDFDocument(url as CFURL))
        let box = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
        #expect(abs(box.width - 841.8898) < 0.01 && abs(box.height - 595.2756) < 0.01)
        #expect(names(f.out) == ["Sheet.pdf"])
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func pdfHasOnePagePerSheet() async throws {
        let f = try fixture(photos: 7)
        let before = try fingerprints(f.source, f.ids)
        let d = LayoutDocument(grid: GridPreset(columns: 3, rows: 2), photoIDs: f.ids, resolution: .standard)
        let url = f.out.appending(path: "Sheet.pdf")
        let written = try await service().export(
            d, fileNames: [:], source: f.source, to: url, format: .pdf, protected: protected(f.source, f.ids))
        #expect(written == [url])
        #expect(try #require(CGPDFDocument(url as CFURL)).numberOfPages == 2)
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func collagePDFHasOnePage() async throws {
        let f = try fixture(photos: 7)
        let d = LayoutDocument(kind: .collage, template: .twoOverThree, photoIDs: f.ids, resolution: .standard)
        let url = f.out.appending(path: "Collage.pdf")
        let written = try await service().export(
            d, fileNames: [:], source: f.source, to: url, format: .pdf, protected: protected(f.source, f.ids))
        #expect(written == [url])
        #expect(try #require(CGPDFDocument(url as CFURL)).numberOfPages == 1)
    }

    @Test func multiPagePNGWritesNumberedFiles() async throws {
        let f = try fixture(photos: 7)
        let before = try fingerprints(f.source, f.ids)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        let written = try await service().export(
            d, fileNames: [:], source: f.source, to: f.out.appending(path: "Sheet.png"), format: .png,
            protected: protected(f.source, f.ids))
        #expect(written.map(\.lastPathComponent) == ["Sheet 1.png", "Sheet 2.png"])
        #expect(names(f.out) == ["Sheet 1.png", "Sheet 2.png"])
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func multiPagePNGStopsWhenAPageNameExists() async throws {
        let f = try fixture(photos: 7)
        let before = try fingerprints(f.source, f.ids)
        let taken = f.out.appending(path: "Sheet 2.png")
        try Data([1, 2, 3]).write(to: taken)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        do {
            _ = try await service().export(
                d, fileNames: [:], source: f.source, to: f.out.appending(path: "Sheet.png"), format: .png,
                protected: protected(f.source, f.ids))
            Issue.record("expected cannotWrite")
        } catch let error as PhotoExportError {
            guard case .cannotWrite(let message) = error else { Issue.record("wrong error \(error)"); return }
            #expect(message.contains("Sheet 2.png"))
        }
        #expect(names(f.out) == ["Sheet 2.png"])
        #expect(try Data(contentsOf: taken) == Data([1, 2, 3]))
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func exportOverASessionPhotoIsRefused() async throws {
        let f = try fixture()
        let photo = f.source.appending(path: f.ids[0])
        let before = try FileFingerprint(of: photo)
        let link = f.out.appending(path: "link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: photo)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        for dest in [f.source.appending(path: "IMG_0001.PNG"), f.source.appending(path: "img_0001.png"), link] {
            await #expect(throws: PhotoExportError.wouldReplaceOriginal) {
                try await service().export(
                    d, fileNames: [:], source: f.source, to: dest, format: .png, protected: protected(f.source, f.ids))
            }
        }
        #expect(try FileFingerprint(of: photo) == before)
        #expect(names(f.source) == f.ids.sorted())
        #expect(names(f.out) == ["link.png"])
    }

    @Test func exportWithAMissingPhotoWritesNothing() async throws {
        let f = try fixture()
        let before = try fingerprints(f.source, f.ids)
        let d = LayoutDocument(photoIDs: f.ids + ["gone.png"], resolution: .standard)
        await #expect(throws: PhotoExportError.originalMissing) {
            try await service().export(
                d, fileNames: [:], source: f.source, to: f.out.appending(path: "Sheet.pdf"), format: .pdf,
                protected: protected(f.source, f.ids))
        }
        #expect(names(f.out).isEmpty)
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func failedPDFWriteLeavesNoTempFile() async throws {
        let f = try fixture()
        let before = try fingerprints(f.source, f.ids)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        let svc = service(writer: ImageExportRepository(fileOps: FailingMoveOps()))
        do {
            _ = try await svc.export(
                d, fileNames: [:], source: f.source, to: f.out.appending(path: "Sheet.pdf"), format: .pdf,
                protected: protected(f.source, f.ids))
            Issue.record("expected cannotWrite")
        } catch let error as PhotoExportError {
            guard case .cannotWrite = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(names(f.out).isEmpty)
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func cancelledExportLeavesNothing() async throws {
        let f = try fixture()
        let before = try fingerprints(f.source, f.ids)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        let svc = service()
        let prot = protected(f.source, f.ids)
        let url = f.out.appending(path: "Sheet.pdf")
        let task = Task { try await svc.export(d, fileNames: [:], source: f.source, to: url, format: .pdf, protected: prot) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(names(f.out).isEmpty)
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test(arguments: [LayoutExportFormat.png, .pdf])
    func unreadablePhotoWritesNothing(format: LayoutExportFormat) async throws {
        let f = try fixture()
        try Data("not an image".utf8).write(to: f.source.appending(path: "bad.png"))
        let before = try fingerprints(f.source, f.ids + ["bad.png"])
        let url = f.out.appending(path: "Sheet.\(format.fileExtension)")
        try Data([9, 9]).write(to: url)
        let d = LayoutDocument(photoIDs: f.ids + ["bad.png"], resolution: .standard)
        await #expect(throws: PhotoExportError.cannotRead) {
            try await service().export(
                d, fileNames: [:], source: f.source, to: url, format: format, protected: protected(f.source, f.ids))
        }
        #expect(try Data(contentsOf: url) == Data([9, 9]))
        #expect(names(f.out) == [url.lastPathComponent])
        #expect(try fingerprints(f.source, f.ids + ["bad.png"]) == before)
    }

    @Test func numberedPageThatAppearsDuringTheExportIsNotReplaced() async throws {
        let f = try fixture(photos: 7)
        let before = try fingerprints(f.source, f.ids)
        let late = f.out.appending(path: "Sheet 2.png")
        let tiny = try TestImages.solid((1, 2, 3))
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        // The file appears after the preflight, while page 1 draws.
        do {
            _ = try await service().export(
                d, fileNames: [:], source: f.source, to: f.out.appending(path: "Sheet.png"), format: .png,
                protected: protected(f.source, f.ids),
                images: { _, _ in
                    try? Data([7]).write(to: late)
                    return tiny
                })
            Issue.record("expected cannotWrite")
        } catch let error as PhotoExportError {
            guard case .cannotWrite = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(try Data(contentsOf: late) == Data([7]))
        #expect(names(f.out) == ["Sheet 2.png"])
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test(arguments: [LayoutExportFormat.png, .pdf])
    func cancelDuringTheWriteLeavesNothing(format: LayoutExportFormat) async throws {
        let f = try fixture(photos: 7)
        let before = try fingerprints(f.source, f.ids)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        let svc = service()
        let prot = protected(f.source, f.ids)
        let url = f.out.appending(path: "Sheet.\(format.fileExtension)")
        let tiny = try TestImages.solid((1, 2, 3))
        let handle = TaskBox()
        let calls = Recorder()
        let task = Task {
            try await svc.export(
                d, fileNames: [:], source: f.source, to: url, format: format, protected: prot,
                images: { _, _ in
                    calls.add(0)
                    // The 7th photo draws on page 2.
                    if calls.calls.count == 7 { handle.cancel() }
                    return tiny
                })
        }
        handle.set(task)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(names(f.out).isEmpty)
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func existingDestinationIsReplacedAtomically() async throws {
        let f = try fixture()
        let before = try fingerprints(f.source, f.ids)
        let url = f.out.appending(path: "Sheet.png")
        try Data([9]).write(to: url)
        let d = LayoutDocument(photoIDs: f.ids, resolution: .standard)
        _ = try await service().export(
            d, fileNames: [:], source: f.source, to: url, format: .png, protected: protected(f.source, f.ids))
        #expect(try pngSize(url).0 == 1754)
        #expect(names(f.out) == ["Sheet.png"])
        #expect(try fingerprints(f.source, f.ids) == before)
    }

    @Test func pageURLsNumberOnlyMultiPagePNG() {
        let url = URL(filePath: "/o/Sheet.png")
        #expect(LayoutExportService.pageURLs(for: url, pageCount: 1, format: .png) == [url])
        #expect(LayoutExportService.pageURLs(for: url, pageCount: 3, format: .pdf) == [url])
        #expect(LayoutExportService.pageURLs(for: url, pageCount: 2, format: .png).map(\.lastPathComponent)
            == ["Sheet 1.png", "Sheet 2.png"])
    }

    @Test func previewImageFitsTheMaxPixel() async throws {
        let f = try fixture()
        let d = LayoutDocument(photoIDs: f.ids)
        let page = LayoutEngine.pages(for: d)[0]
        let image = try #require(await service().previewImage(
            of: page, document: d, fileNames: [:], maxPixel: 800, source: f.source))
        // The dpi is a whole number, so the width is near maxPixel (within 5 %), not equal.
        #expect(abs(image.width - 800) <= 40)
    }

    @Test(.timeLimit(.minutes(2)))
    func thousandPhotosExportWithoutFullDecode() async throws {
        let dir = try TempDir()
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        let out = dir.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let originals = (0..<4).map { "orig\($0).jpg" }
        for name in originals {
            try TestImages.save(
                try TestImages.solid((UInt8(name.count), 100, 50), width: 4000, height: 3000),
                to: source.appending(path: name), type: .jpeg)
        }
        let before = try originals.map { try FileFingerprint(of: source.appending(path: $0)) }
        let ids = (0..<1000).map { String(format: "p%04d.jpg", $0) }
        for (i, id) in ids.enumerated() {
            try FileManager.default.createSymbolicLink(
                at: source.appending(path: id), withDestinationURL: source.appending(path: originals[i % 4]))
        }
        let d = LayoutDocument(photoIDs: ids, resolution: .high)
        let page = LayoutEngine.pages(for: d)[0]
        let needed = LayoutEngine.neededPixels(
            for: page.cells[0].imageArea, source: PixelSize(width: 4000, height: 3000), fit: .fit, dpi: 300)
        let tiny = try TestImages.solid((10, 20, 30))
        let recorder = Recorder()
        let url = out.appending(path: "Big.pdf")
        _ = try await service().export(
            d, fileNames: [:], source: source, to: url, format: .pdf, protected: protected(source, ids),
            images: { _, maxPixel in
                recorder.add(maxPixel)
                return tiny
            })
        #expect(recorder.calls.count == 1000)
        #expect(recorder.calls.allSatisfy { $0 > 0 && $0 <= needed && $0 < 4000 })
        #expect(try #require(CGPDFDocument(url as CFURL)).numberOfPages == 167)
        #expect(names(out) == ["Big.pdf"])
        #expect(try originals.map { try FileFingerprint(of: source.appending(path: $0)) } == before)
    }

    @Test func protectedFilesRefuseTheOriginalByAnyNameForm() throws {
        let f = try fixture()
        let original = f.source.appending(path: f.ids[0])
        let hard = f.out.appending(path: "hard.png")
        try FileManager.default.linkItem(at: original, to: hard)
        let p = ProtectedFiles(source: f.source, mediaIDs: [], otherPaths: [])
        #expect(p.refuses(f.source.appending(path: "IMG_0001.PNG"), original: original))
        #expect(p.refuses(hard, original: original))
        #expect(!p.refuses(f.out.appending(path: "new.png"), original: original))
        #expect(!p.refuses(f.out.appending(path: "new.png"), original: nil))
    }
}
