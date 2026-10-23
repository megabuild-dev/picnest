import Foundation
import Testing
@testable import PicnestCore

@Suite struct EmbedImagesPartialTests {
    @Test func oneUnreadableImageFailsOnlyThatURL() async throws {
        let e = FakeEmbedder(dimension: 2, images: ["a.jpg": [1, 0], "c.jpg": [0, 1]])
        let a = URL(fileURLWithPath: "/x/a.jpg"), b = URL(fileURLWithPath: "/x/b.jpg"), c = URL(fileURLWithPath: "/x/c.jpg")
        let r = await e.embedImagesPartial([a, b, c])
        #expect(r.count == 3)
        #expect(try r[a]?.get() == [1, 0])
        #expect(try r[c]?.get() == [0, 1])
        #expect(throws: EmbedderError.unreadable(b)) { try r[b]?.get() }
    }

    @Test func allReadableUsesOneBatchCall() async throws {
        let e = FakeEmbedder(dimension: 2, images: ["a.jpg": [1, 0], "c.jpg": [0, 1]])
        let a = URL(fileURLWithPath: "/x/a.jpg"), c = URL(fileURLWithPath: "/x/c.jpg")
        let r = await e.embedImagesPartial([a, c])
        #expect(try r[a]?.get() == [1, 0])
        #expect(e.imageCallCount == 1)
    }
}
