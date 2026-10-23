import Foundation
import Testing
@testable import PicnestCore

struct ThumbnailServiceTests {
    @Test func thumbnailReadsTheFileUnderTheSource() async throws {
        let dir = try TempDir()
        let folder = dir.url.appending(path: "Trip", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TestImages.writeJPEG(to: folder.appending(path: "beach.jpg"), color: (20, 90, 200), size: 1200)
        let media = MediaFile(id: "Trip/beach.jpg", relativePath: "Trip/beach.jpg", kind: .image, size: 1,
                              modified: Date(timeIntervalSince1970: 0))
        let service = ThumbnailService(images: ImageRepository())
        let thumb = try #require(await service.thumbnail(for: media, source: dir.url, maxPixel: 200))
        #expect(max(thumb.width, thumb.height) <= 200)
        let again = try #require(await service.thumbnail(for: media, source: dir.url, maxPixel: 200))
        #expect(again === thumb)  // The shared cache holds it.
    }

    @Test func missingFileGivesNil() async {
        let media = MediaFile(id: "none.jpg", relativePath: "none.jpg", kind: .image, size: 1,
                              modified: Date(timeIntervalSince1970: 0))
        let source = URL(filePath: "/nonexistent-\(UUID().uuidString)", directoryHint: .isDirectory)
        #expect(await ThumbnailService(images: ImageRepository()).thumbnail(for: media, source: source, maxPixel: 200) == nil)
    }

    @Test func maxPixelRoundsTwiceTheWidthUpToAStep() {
        #expect(ThumbnailService.maxPixel(forTileWidth: 0) == 200)
        #expect(ThumbnailService.maxPixel(forTileWidth: 90) == 200)
        #expect(ThumbnailService.maxPixel(forTileWidth: 150) == 400)
        #expect(ThumbnailService.maxPixel(forTileWidth: 200) == 400)
        #expect(ThumbnailService.maxPixel(forTileWidth: 380) == 800)
        #expect(ThumbnailService.maxPixel(forTileWidth: 2000) == 1600)
    }
}
