import Foundation
import Testing
@testable import PicnestCore

struct DuplicateServiceTests {
    private let service = DuplicateService()
    private static let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func media(_ id: MediaID, size: Int64 = 100, path: String? = nil, kind: MediaKind = .image) -> MediaFile {
        MediaFile(id: id, relativePath: path ?? id, kind: kind, size: size, modified: Self.date)
    }

    /// A unit vector in the plane of the first 2 axes, at cosine `c` to `[1, 0, 0, 0]` (negative `side`
    /// puts it on the other side of that axis).
    private func v(_ c: Float, side: Float = 1) -> Vector {
        [c, side * (1 - c * c).squareRoot(), 0, 0]
    }

    /// Unit vector at `angle` radians in the plane of the first 2 axes.
    private func angle(_ a: Float) -> Vector {
        [cos(a), sin(a), 0, 0]
    }

    private func groups(
        _ media: [MediaFile], hashes: [MediaID: String] = [:], vectors: [MediaID: Vector] = [:],
        pixels: [MediaID: Int] = [:], dates: [MediaID: Date] = [:], dismissed: Set<String> = []
    ) -> [DuplicateGroup] {
        service.groups(
            media: media, hashes: hashes, vectors: vectors, pixels: pixels, dates: dates, similarity: 0.95,
            dismissed: dismissed)
    }

    @Test func exactGroupFromSameBytes() {
        let m = [media("a.jpg"), media("b.jpg"), media("c.jpg"), media("d.jpg", size: 200)]
        // c.jpg has its own hash; d.jpg has the hash of a and b but another size.
        let g = groups(m, hashes: ["a.jpg": "h1", "b.jpg": "h1", "c.jpg": "h2", "d.jpg": "h1"])
        #expect(g.count == 1)
        #expect(g.first?.kind == .exact)
        #expect(Set(g.first?.ids ?? []) == ["a.jpg", "b.jpg"])
        #expect(g.first?.keepIDs.count == 1)
    }

    @Test func similarGroupAboveThreshold() {
        let m = [media("a.jpg"), media("b.jpg"), media("c.jpg")]
        let g = groups(m, vectors: ["a.jpg": v(1), "b.jpg": v(0.97), "c.jpg": v(0.90, side: -1)])
        #expect(g.count == 1)
        #expect(g.first?.kind == .similar)
        #expect(Set(g.first?.ids ?? []) == ["a.jpg", "b.jpg"])
    }

    @Test func similarityIsCosineOfUnnormalizedVectors() {
        let m = [media("a.jpg"), media("b.jpg")]
        let g = groups(m, vectors: ["a.jpg": v(1).map { $0 * 3 }, "b.jpg": v(0.97).map { $0 * 0.5 }])
        #expect(g.count == 1)
    }

    /// A~B and B~C at 0.96, A~C at about 0.84. The pairs join into 1 group, then the group keeps only the
    /// photos similar to its Keep photo. The other photos make new groups with the same rule.
    @Test func chainJoinsIntoOneGroup() {
        let step = acos(Float(0.96))
        let m = [media("a.jpg"), media("b.jpg"), media("c.jpg")]
        let vectors = ["a.jpg": angle(0), "b.jpg": angle(step), "c.jpg": angle(2 * step)]
        // B is the Keep photo (most pixels) and is similar to A and C: 1 group of 3.
        var g = groups(m, vectors: vectors, pixels: ["a.jpg": 1, "b.jpg": 2, "c.jpg": 1])
        #expect(g.count == 1)
        #expect(g.first?.ids == ["b.jpg", "a.jpg", "c.jpg"])
        #expect(g.first?.keepIDs == ["b.jpg"])
        // A is the Keep photo and is not similar to C: the group is A, B. C alone is in no group.
        g = groups(m, vectors: vectors, pixels: ["a.jpg": 2, "b.jpg": 1, "c.jpg": 1])
        #expect(g.count == 1)
        #expect(g.first?.ids == ["a.jpg", "b.jpg"])
        #expect(g.first?.keepIDs == ["a.jpg"])
    }

    /// A chain of 4: A is the Keep photo of the first group (A, B). C and D make a new group.
    @Test func photosLeftOutOfAGroupMakeNewGroups() {
        let step = acos(Float(0.96))
        let m = [media("a.jpg"), media("b.jpg"), media("c.jpg"), media("d.jpg")]
        let vectors = ["a.jpg": angle(0), "b.jpg": angle(step), "c.jpg": angle(2 * step), "d.jpg": angle(3 * step)]
        let g = groups(m, vectors: vectors, pixels: ["a.jpg": 4, "b.jpg": 1, "c.jpg": 3, "d.jpg": 1])
        #expect(g.map(\.ids) == [["a.jpg", "b.jpg"], ["c.jpg", "d.jpg"]])
        #expect(g.map(\.keepIDs) == [["a.jpg"], ["c.jpg"]])
    }

    /// Spec 14: the similar search uses only the Keep photo of each exact group, so a similar group never
    /// holds 2 photos of 1 exact group. The Keep photo can be in its exact group and in 1 similar group.
    @Test func exactGroupNotRepeatedAsSimilar() throws {
        // p1 and p2 are exact copies. They tie on pixels, size, date, and path length, so p1 (the first
        // path) is the Keep photo. q and r are similar to each other and to the copies.
        let m = [media("p1.jpg"), media("p2.jpg"), media("q.jpg", size: 50), media("r.jpg", size: 60)]
        let g = groups(
            m, hashes: ["p1.jpg": "h", "p2.jpg": "h"],
            vectors: ["p1.jpg": v(1), "p2.jpg": v(1), "q.jpg": v(0.98), "r.jpg": v(0.97)])
        try #require(g.map(\.kind) == [.exact, .similar])
        #expect(g[0].ids == ["p1.jpg", "p2.jpg"])
        #expect(Set(g[1].ids) == ["p1.jpg", "q.jpg", "r.jpg"])
        #expect(!g[1].ids.contains("p2.jpg"))
        #expect(g[1].keepIDs.contains("p1.jpg"))
        // No photo is in 2 groups of the same kind, and only the exact Keep photo is in 2 groups.
        let twice = Set(g[0].ids).intersection(g[1].ids)
        #expect(twice == g[0].keepIDs)
    }

    /// The exact Keep photo in a similar group is a Keep photo there too, even when another photo is best.
    @Test func exactCopiesAndASimilarPhoto() throws {
        let m = [media("p1.jpg"), media("p2.jpg"), media("q.jpg", size: 500)]
        let g = groups(
            m, hashes: ["p1.jpg": "h", "p2.jpg": "h"],
            vectors: ["p1.jpg": v(1), "p2.jpg": v(1), "q.jpg": v(0.98)])
        try #require(g.map(\.kind) == [.exact, .similar])
        #expect(g[0].keepIDs == ["p1.jpg"])
        #expect(g[1].ids == ["q.jpg", "p1.jpg"])  // q is the larger file, so it is best.
        #expect(g[1].keepIDs == ["q.jpg", "p1.jpg"])
    }

    @Test func bestPhotoOrder() {
        let same = ["a.jpg": v(1), "b.jpg": v(1)]
        // 1. The most pixels.
        var g = groups([media("a.jpg", size: 900), media("b.jpg")], vectors: same, pixels: ["a.jpg": 100, "b.jpg": 200])
        #expect(g.first?.keepIDs == ["b.jpg"])
        #expect(g.first?.ids.first == "b.jpg")
        // 2. Then the largest file.
        g = groups([media("a.jpg", size: 10), media("b.jpg", size: 20)], vectors: same, pixels: ["a.jpg": 100, "b.jpg": 100])
        #expect(g.first?.keepIDs == ["b.jpg"])
        // 3. Then the oldest date.
        g = groups(
            [media("a.jpg"), media("b.jpg")], vectors: same,
            dates: ["a.jpg": Self.date, "b.jpg": Self.date.addingTimeInterval(-60)])
        #expect(g.first?.keepIDs == ["b.jpg"])
        // 4. Then the shortest relative path.
        g = groups([media("a.jpg", path: "deep/folder/a.jpg"), media("b.jpg", path: "longer-b.jpg")], vectors: same)
        #expect(g.first?.keepIDs == ["b.jpg"])
    }

    @Test func atLeastOneKeep() throws {
        let m = (0..<6).map { media("p\($0).jpg") }
        var vectors: [MediaID: Vector] = [:]
        for f in m { vectors[f.id] = v(1) }
        let g = groups(m, hashes: ["p0.jpg": "h", "p1.jpg": "h"], vectors: vectors)
        #expect(!g.isEmpty)
        for group in g {
            #expect(!group.keepIDs.isEmpty)
            try #require(group.ids.count >= 1)
            #expect(group.keepIDs.contains(group.ids[0]))
            #expect(group.keepIDs.isSubset(of: Set(group.ids)))
            #expect(group.ids.count >= 2)
        }
    }

    @Test func dismissedGroupHidden() throws {
        let vectors = ["a.jpg": v(1), "b.jpg": v(0.99), "c.jpg": v(0.98)]
        let first = groups([media("a.jpg"), media("b.jpg")], vectors: vectors)
        let key = try #require(first.first).id
        #expect(key == DuplicateGroup.key(for: ["b.jpg", "a.jpg"]))
        #expect(groups([media("a.jpg"), media("b.jpg")], vectors: vectors, dismissed: [key]).isEmpty)
        // A rescan adds c.jpg: the group changes, so it shows again.
        let again = groups([media("a.jpg"), media("b.jpg"), media("c.jpg")], vectors: vectors, dismissed: [key])
        #expect(again.count == 1)
        #expect(again.first?.ids.count == 3)
    }

    @Test func videosNotGrouped() {
        let m = [media("a.jpg"), media("v.mov", kind: .video), media("w.mov", kind: .video)]
        let g = groups(
            m, hashes: ["a.jpg": "h", "v.mov": "h", "w.mov": "h"],
            vectors: ["a.jpg": v(1), "v.mov": v(1), "w.mov": v(1)])
        #expect(g.isEmpty)
    }

    @Test func photosWithoutHashOrVectorAreNotGrouped() {
        let g = groups([media("a.jpg"), media("b.jpg")])
        #expect(g.isEmpty)
    }

    @Test(.enabled(if: BuildConfig.isRelease, "Run with -c release"))
    func tenThousandVectorsUnder10Seconds() {
        var rng = SplitMix64(seed: 26)
        var media: [MediaFile] = []
        var vectors: [MediaID: Vector] = [:]
        for i in 0..<10_000 {
            let id = "p\(i).jpg"
            media.append(self.media(id))
            vectors[id] = (0..<512).map { _ in Float.random(in: -1...1, using: &rng) }
        }
        // 1 near copy, so the search has 1 group to find.
        vectors["p9999.jpg"] = vectors["p0.jpg"]!.map { $0 * 1.01 }
        let start = ContinuousClock.now
        let g = service.groups(
            media: media, hashes: [:], vectors: vectors, pixels: [:], dates: [:], similarity: 0.95, dismissed: [])
        let elapsed = ContinuousClock.now - start
        print("duplicates of 10000 photos: \(elapsed)")
        #expect(g.count == 1)
        #expect(Set(g.first?.ids ?? []) == ["p0.jpg", "p9999.jpg"])
        #expect(elapsed < .seconds(10))
    }
}
