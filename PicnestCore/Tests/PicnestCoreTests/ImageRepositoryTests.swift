import Foundation
import Testing
@testable import PicnestCore

struct ImageRepositoryTests {
    @Test func thumbnailIsSmall() async throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "big.jpg")
        try TestImages.writeJPEG(to: url, color: (200, 50, 50), size: 2000)
        let repo = ImageRepository()
        let thumb = try #require(await repo.thumbnail(for: url, maxPixel: 400))
        #expect(max(thumb.width, thumb.height) <= 400)
        let again = try #require(await repo.thumbnail(for: url, maxPixel: 400))
        #expect(again === thumb)
    }

    @Test func unreadableFileGivesNil() async throws {
        let dir = try TempDir()
        let url = dir.url.appending(path: "bad.jpg")
        try Data("nope".utf8).write(to: url)
        #expect(await ImageRepository().thumbnail(for: url, maxPixel: 100) == nil)
    }
}
