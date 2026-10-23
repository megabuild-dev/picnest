import Testing
@testable import PicnestCore

@Suite struct CLIPTokenizerTests {
    @Test func tokenizesLikeOpenCLIP() throws {
        let t = try CLIPTokenizer().encode("a photo of a cat")
        #expect(t.count == 77)
        #expect(Array(t.prefix(7)) == [49406, 320, 1125, 539, 320, 2368, 49407])
        #expect(t[7...].allSatisfy { $0 == 0 })
    }
}
