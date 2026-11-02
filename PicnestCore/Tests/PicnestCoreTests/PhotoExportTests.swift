import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PicnestCore

struct PhotoExportTests {
    let images = ImageRepository()

    private func service(writer: ImageExportRepository = ImageExportRepository()) -> PhotoEditService {
        PhotoEditService(thumbnails: ThumbnailService(images: images), images: images, writer: writer)
    }

    private func protected(_ source: URL, ids: Set<MediaID> = []) -> ProtectedFiles {
        ProtectedFiles(source: source, mediaIDs: ids, otherPaths: [])
    }

    private func properties(of url: URL) -> [CFString: Any] {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] ?? [:]
    }

    /// The decoded pixels, with no orientation applied.
    private func decode(_ url: URL) throws -> CGImage {
        let s = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(s, 0, nil))
    }

    private func leftovers(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private func near(_ c: TestImages.RGB, _ r: Int, _ g: Int, _ b: Int, tol: Int = 40) -> Bool {
        abs(Int(c.r) - r) <= tol && abs(Int(c.g) - g) <= tol && abs(Int(c.b) - b) <= tol
    }

    /// A source folder with `IMG_2048.jpg` (80 × 40 quadrants).
    private func fixture(orientation: Int = 1, name: String = "IMG_2048.jpg") throws -> (dir: TempDir, source: URL, original: URL) {
        let dir = try TempDir()
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let original = source.appending(path: name)
        try TestImages.writeQuadrants(to: original, type: .jpeg, width: 80, height: 40, orientation: orientation)
        return (dir, source, original)
    }

    @Test func exportWritesANewFileAndKeepsTheOriginal() async throws {
        let f = try fixture()
        let before = try FileFingerprint(of: f.original)
        var edit = PhotoEdit.original
        edit.rotate(clockwise: true)
        edit.crop = NormalizedRect(x: 0, y: 0, width: 1, height: 0.5)
        let dest = f.source.appending(path: "IMG_2048 edited.jpg")
        let result = try await service().exportCopy(
            of: f.original, edit: edit, to: dest, format: .jpeg, protected: protected(f.source, ids: ["IMG_2048.jpg"]))
        #expect(result == dest)
        let out = try decode(dest)
        let expected = PhotoEditService.outputSize(of: edit, source: PixelSize(width: 80, height: 40))
        #expect(out.width == expected.width && out.height == expected.height)
        #expect(out.width == 40 && out.height == 40)
        #expect(try FileFingerprint(of: f.original) == before)
        #expect(leftovers(in: f.source) == ["IMG_2048 edited.jpg", "IMG_2048.jpg"])
    }

    @Test(arguments: ["IMG_2048.jpg", "img_2048.JPG"])
    func exportToTheOriginalPathIsRefused(name: String) async throws {
        let f = try fixture()
        let before = try FileFingerprint(of: f.original)
        await #expect(throws: PhotoExportError.wouldReplaceOriginal) {
            try await service().exportCopy(
                of: f.original, edit: .original, to: f.source.appending(path: name), format: .jpeg,
                protected: ProtectedFiles(source: f.source, mediaIDs: [], otherPaths: []))
        }
        #expect(try FileFingerprint(of: f.original) == before)
        #expect(leftovers(in: f.source) == ["IMG_2048.jpg"])
    }

    @Test func exportOverAHardLinkOrSymlinkOfTheOriginalIsRefused() async throws {
        let f = try fixture()
        let before = try FileFingerprint(of: f.original)
        let link = f.source.appending(path: "link.jpg")
        let hard = f.source.appending(path: "hard.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.original)
        try FileManager.default.linkItem(at: f.original, to: hard)
        for dest in [link, hard] {
            await #expect(throws: PhotoExportError.wouldReplaceOriginal) {
                try await service().exportCopy(
                    of: f.original, edit: .original, to: dest, format: .jpeg, protected: protected(f.source))
            }
        }
        #expect(try FileFingerprint(of: f.original) == before)
    }

    @Test func exportOverAnotherSessionPhotoIsRefused() async throws {
        let f = try fixture()
        let other = f.source.appending(path: "Trip").appending(path: "Other.jpg")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TestImages.writeJPEG(to: other, color: (1, 2, 3))
        let before = try FileFingerprint(of: other)
        // Other letter case and decomposed letters are the same photo.
        for name in ["Trip/Other.jpg", "trip/OTHER.JPG"] {
            await #expect(throws: PhotoExportError.wouldReplaceOriginal) {
                try await service().exportCopy(
                    of: f.original, edit: .original, to: f.source.appending(path: name), format: .jpeg,
                    protected: protected(f.source, ids: ["IMG_2048.jpg", "Trip/Other.jpg"]))
            }
        }
        #expect(try FileFingerprint(of: other) == before)
    }

    @Test func exportOverALinkToAnotherSessionPhotoIsRefused() async throws {
        let f = try fixture()
        let other = f.source.appending(path: "Other.jpg")
        try TestImages.writeJPEG(to: other, color: (1, 2, 3))
        let before = try FileFingerprint(of: other)
        let link = f.source.appending(path: "link.jpg")
        let hard = f.source.appending(path: "hard.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        try FileManager.default.linkItem(at: other, to: hard)
        for dest in [link, hard] {
            await #expect(throws: PhotoExportError.wouldReplaceOriginal) {
                try await service().exportCopy(
                    of: f.original, edit: .original, to: dest, format: .jpeg,
                    protected: protected(f.source, ids: ["IMG_2048.jpg", "Other.jpg"]))
            }
        }
        #expect(try FileFingerprint(of: other) == before)
        #expect(leftovers(in: f.source) == ["IMG_2048.jpg", "Other.jpg", "hard.jpg", "link.jpg"])
    }

    @Test func otherPathsResolveSymlinks() throws {
        let dir = try TempDir()
        let real = dir.url.appending(path: "RealTrash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = dir.url.appending(path: "Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let p = ProtectedFiles(source: source, mediaIDs: [], otherPaths: [alias.appending(path: "Gone.jpg").path])
        #expect(p.contains(real.appending(path: "gone.jpg")))
        #expect(p.contains(alias.appending(path: "Gone.jpg")))
    }

    @Test func exportKeepsGPS() async throws {
        let f = try fixture()
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 10.5, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 20.25, kCGImagePropertyGPSLongitudeRef: "E",
        ]
        try TestImages.writeQuadrants(
            to: f.original, type: .jpeg, width: 80, height: 40, extra: [kCGImagePropertyGPSDictionary: gps])
        let dest = f.source.appending(path: "gps edited.jpg")
        _ = try await service().exportCopy(
            of: f.original, edit: .original, to: dest, format: .jpeg, protected: protected(f.source))
        let out = properties(of: dest)[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        #expect((out?[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue == 10.5)
        #expect((out?[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue == 20.25)
    }

    @Test func aCancelledExportWritesNothing() async throws {
        let f = try fixture()
        let dest = f.source.appending(path: "x edited.jpg")
        let svc = service()
        let prot = protected(f.source)
        let task = Task { try await svc.exportCopy(of: f.original, edit: .original, to: dest, format: .jpeg, protected: prot) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(leftovers(in: f.source) == ["IMG_2048.jpg"])
    }

    @Test func aCancelledWriteRemovesTheTempFile() async throws {
        let dir = try TempDir()
        let image = try TestImages.quadrantImage(width: 20, height: 10)
        let task = Task {
            try ImageExportRepository().write(
                image, to: dir.url.appending(path: "x.jpg"), format: .jpeg, quality: 0.9, properties: [:], replacing: false)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(leftovers(in: dir.url).isEmpty)
    }

    @Test func protectedFilesCompareCanonicalNfcAndCase() throws {
        let dir = try TempDir()
        let source = dir.url.appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let nfc = "caf\u{E9}.jpg", nfd = "cafe\u{301}.jpg"
        let p = ProtectedFiles(source: source, mediaIDs: [nfc, "Sub/B.JPG"], otherPaths: ["/Users/x/.Trash/Gone.jpg"])
        #expect(p.contains(source.appending(path: nfd)))
        #expect(p.contains(source.appending(path: "CAFÉ.JPG")))
        #expect(p.contains(source.appending(path: "sub").appending(path: "b.jpg")))
        #expect(p.contains(URL(filePath: "/Users/x/.Trash/gone.JPG")))
        #expect(!p.contains(source.appending(path: "other.jpg")))
        #expect(!p.contains(dir.url.appending(path: "café.jpg")))  // Outside the source folder.
    }

    @Test func exportOfOrientationSixIsUprightWithOrientationOne() async throws {
        let f = try fixture(orientation: 6)  // Stored 80 × 40, shown 40 × 80.
        let dest = f.source.appending(path: "o6 edited.jpg")
        _ = try await service().exportCopy(
            of: f.original, edit: .original, to: dest, format: .jpeg, protected: protected(f.source))
        let props = properties(of: dest)
        #expect((props[kCGImagePropertyOrientation] as? NSNumber)?.intValue == 1)
        #expect((props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 40)
        #expect((props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 80)
        let out = try decode(dest)
        #expect(out.width == 40 && out.height == 80)
        #expect(near(TestImages.color(at: (3, 3), in: out), 255, 0, 0))
        #expect(near(TestImages.color(at: (36, 3), in: out), 0, 255, 0))
        #expect(near(TestImages.color(at: (3, 76), in: out), 0, 0, 255))
        #expect(near(TestImages.color(at: (36, 76), in: out), 255, 255, 255))
    }

    @Test func exportKeepsTheExifDate() async throws {
        let f = try fixture(name: "dated.jpg")
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        try TestImages.writeJPEG(to: f.original, color: (10, 20, 30), exifDate: date, size: 64)
        let dest = f.source.appending(path: "dated edited.jpg")
        _ = try await service().exportCopy(
            of: f.original, edit: .original, to: dest, format: .jpeg, protected: protected(f.source))
        let want = (properties(of: f.original)[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String
        let got = (properties(of: dest)[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String
        #expect(want != nil)
        #expect(got == want)
    }

    @Test(arguments: ExportFormat.allCases)
    func exportInEachFormatHasItsType(format: ExportFormat) async throws {
        let f = try fixture()
        let dest = f.source.appending(path: "x edited.\(format.fileExtension)")
        _ = try await service().exportCopy(
            of: f.original, edit: .original, to: dest, format: format, protected: protected(f.source))
        let s = try #require(CGImageSourceCreateWithURL(dest as CFURL, nil))
        #expect(CGImageSourceGetType(s) as String? == format.utType.identifier)
    }

    @Test func failedWriteLeavesNoFile() async throws {
        let f = try fixture()
        let folder = f.dir.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let before = try FileFingerprint(of: f.original)
        do {
            _ = try await service().exportCopy(
                of: f.original, edit: .original, to: folder.appending(path: "x.jpg"), format: .jpeg,
                protected: protected(f.source))
            Issue.record("expected cannotWrite")
        } catch let error as PhotoExportError {
            guard case .cannotWrite = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(leftovers(in: folder).isEmpty)
        #expect(try FileFingerprint(of: f.original) == before)
    }

    @Test func failedMoveRemovesTheTempFile() async throws {
        let f = try fixture()
        let folder = f.dir.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let svc = service(writer: ImageExportRepository(fileOps: FailingMoveOps()))
        do {
            _ = try await svc.exportCopy(
                of: f.original, edit: .original, to: folder.appending(path: "x.jpg"), format: .jpeg,
                protected: protected(f.source))
            Issue.record("expected cannotWrite")
        } catch let error as PhotoExportError {
            guard case .cannotWrite = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(leftovers(in: folder).isEmpty)
    }

    @Test func exportOfAJPEGWithAnEmbeddedThumbnailIsFullSize() async throws {
        let f = try fixture()
        try TestImages.writeQuadrants(
            to: f.original, type: .jpeg, width: 1200, height: 800, extra: [kCGImageDestinationEmbedThumbnail: true])
        // The fixture must really hold a thumbnail, or this test proves nothing.
        let s = try #require(CGImageSourceCreateWithURL(f.original as CFURL, nil))
        let embedded = try #require(CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailFromImageIfAbsent: true] as CFDictionary))
        #expect(max(embedded.width, embedded.height) < 1200)
        let dest = f.source.appending(path: "big edited.jpg")
        _ = try await service().exportCopy(
            of: f.original, edit: .original, to: dest, format: .jpeg, protected: protected(f.source))
        let out = try decode(dest)
        #expect(out.width == 1200 && out.height == 800)
    }

    @Test func exportKeepsADisplayP3ColorSpace() async throws {
        let f = try fixture()
        try TestImages.writeQuadrants(
            to: f.original, type: .jpeg, width: 80, height: 40, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let dest = f.source.appending(path: "p3 edited.jpg")
        var edit = PhotoEdit.original
        edit[.exposure] = 10
        _ = try await service().exportCopy(
            of: f.original, edit: edit, to: dest, format: .jpeg, protected: protected(f.source))
        #expect(try decode(dest).colorSpace?.name as String? == CGColorSpace.displayP3 as String)
    }

    @Test func exportWithMissingOriginalThrows() async throws {
        let f = try fixture()
        await #expect(throws: PhotoExportError.originalMissing) {
            try await service().exportCopy(
                of: f.source.appending(path: "gone.jpg"), edit: .original,
                to: f.source.appending(path: "gone edited.jpg"), format: .jpeg, protected: protected(f.source))
        }
        #expect(leftovers(in: f.source) == ["IMG_2048.jpg"])
    }

    @Test func replacingAnUnprotectedFileWorks() async throws {
        let f = try fixture()
        let dest = f.source.appending(path: "a edited.jpg")
        try TestImages.writeJPEG(to: dest, color: (9, 9, 9), size: 8)
        _ = try await service().exportCopy(
            of: f.original, edit: .original, to: dest, format: .jpeg, protected: protected(f.source, ids: ["IMG_2048.jpg"]))
        #expect(try decode(dest).width == 80)
        #expect(leftovers(in: f.source) == ["IMG_2048.jpg", "a edited.jpg"])
    }

    @Test func uniqueNameAddsANumber() throws {
        let dir = try TempDir()
        try TestImages.writeJPEG(to: dir.url.appending(path: "IMG edited.jpg"), color: (1, 1, 1))
        #expect(PhotoEditService.uniqueName("IMG edited.jpg", in: dir.url) == "IMG edited 2.jpg")
        #expect(PhotoEditService.uniqueName("IMG edited.jpg".decomposedStringWithCanonicalMapping, in: dir.url) == "IMG edited 2.jpg")
        #expect(PhotoEditService.uniqueName("fresh.jpg", in: dir.url) == "fresh.jpg")
    }

    @Test func alphaToJPEGHasAWhiteBackground() async throws {
        let f = try fixture()
        let png = f.source.appending(path: "clear.png")
        try TestImages.save(try TestImages.solid((255, 0, 0), width: 16, height: 16, alpha: 0), to: png, type: .png)
        let dest = f.source.appending(path: "clear edited.jpg")
        _ = try await service().exportCopy(
            of: png, edit: .original, to: dest, format: .jpeg, protected: protected(f.source))
        let c = TestImages.color(at: (8, 8), in: try decode(dest))
        #expect(near(c, 255, 255, 255, tol: 6), "\(c)")
    }
}
