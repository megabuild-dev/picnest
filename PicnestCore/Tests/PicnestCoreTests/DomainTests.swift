import Foundation
import ImageIO
import Testing
@testable import PicnestCore

@Test func photoStateNotSure() {
    let a = Assignment(categoryID: UUID(), score: 0.3, secondCategoryID: nil, secondScore: nil, percent: 40, uncertain: true)
    #expect(PhotoState.auto(a).isNotSure)
    #expect(PhotoState.heldNotSure(a.with(uncertain: false)).isNotSure)
    #expect(!PhotoState.auto(a.with(uncertain: false)).isNotSure)
    #expect(!PhotoState.manual(UUID()).isNotSure)
    #expect(PhotoState.manual(UUID()).isManual)
    #expect(!PhotoState.dontMove.isManual)
}

@Test func sessionRoundTripsThroughJSON() throws {
    let cat1 = UUID(), cat2 = UUID()
    let a = Assignment(categoryID: cat1, score: 0.31, secondCategoryID: cat2, secondScore: 0.2, percent: 77, uncertain: false)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let files = ["a.jpg", "b.jpg", "c.jpg", "d.jpg", "e.jpg"].map {
        MediaFile(id: $0, relativePath: $0, kind: .image, size: 10, modified: date)
    }
    let session = Session(
        sourcePath: "/x/src",
        candidateList: .everyday,
        categories: [Category(id: cat1, displayName: "Food", emoji: "🍜", prompts: ["a photo of food"], exampleIDs: ["a.jpg"], order: 0)],
        states: [
            "a.jpg": .auto(a), "b.jpg": .manual(cat2), "c.jpg": .heldNotSure(a),
            "d.jpg": .dontMove, "e.jpg": .unreadable,
        ],
        scan: ScanResult(
            media: files,
            dates: ["a.jpg": PhotoDate(date: date, source: .exif)],
            skipped: [.hidden: 2, .webFile: 1]
        ),
        sortedAt: date
    )
    let data = try JSONEncoder().encode(session)
    let decoded = try JSONDecoder().decode(Session.self, from: data)
    #expect(decoded == session)
}

/// Phase 12: a session.json saved with an old list still decodes. New sessions save "all".
@Test func oldCandidateListValuesStillDecode() throws {
    let session = Session(
        sourcePath: "/x/src", candidateList: .all, categories: [], states: [:],
        scan: ScanResult(media: [], dates: [:], skipped: [:]), sortedAt: nil)
    let json = try #require(String(data: JSONEncoder().encode(session), encoding: .utf8))
    #expect(json.contains(#""candidateList":"all""#))
    for old in ["artStudio", "everyday"] {
        let data = Data(json.replacingOccurrences(of: #""candidateList":"all""#, with: #""candidateList":"\#(old)""#).utf8)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        #expect(decoded.candidateList.rawValue == old)
    }
}

@Test func defaultSortOptions() {
    let o = SortOptions.defaults(source: URL(filePath: "/x/Zalo export"))
    #expect(o.destination.path == "/x/Zalo export - sorted")
    #expect(o.mode == .copy && !o.dateFolders && !o.rename && o.notSureChoice == .acceptBestGuess)
}

@Test func testImagesWriteExifDate() throws {
    let dir = try TempDir()
    let url = dir.url.appending(path: "p.jpg")
    let date = Date(timeIntervalSince1970: 1_600_000_000)
    try TestImages.writeJPEG(to: url, color: (255, 0, 0), exifDate: date)
    let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
    let exif = try #require(props[kCGImagePropertyExifDictionary] as? [CFString: Any])
    let text = try #require(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
    let f = DateFormatter()
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    let back = try #require(f.date(from: text))
    #expect(abs(back.timeIntervalSince(date)) < 1)
}

@Test func fakeEmbedderRecordsCalls() async throws {
    let e = FakeEmbedder(dimension: 2, images: ["a.jpg": [1, 0]], texts: ["hi": [0, 1]])
    let v = try await e.embedImages([URL(filePath: "/q/a.jpg")])
    #expect(v == [[1, 0]])
    #expect(try await e.embedTexts(["hi"]) == [[0, 1]])
    await #expect(throws: EmbedderError.unreadable(URL(filePath: "/q/zz.jpg"))) {
        try await e.embedImages([URL(filePath: "/q/zz.jpg")])
    }
    #expect(e.imageCallCount == 2 && e.textCallCount == 1)
    #expect(e.imageURLs.map(\.lastPathComponent) == ["a.jpg", "zz.jpg"])
}
